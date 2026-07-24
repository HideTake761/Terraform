# バックエンド & Provider設定
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  backend "gcs" {
    bucket = "terraform-k8s-go-gcp" # コンソールで作ったバケット名【マスキング！】
    prefix = "terraform/state" # バケット内の保存先フォルダ名(基本はこのままでOK)
  }
}

provider "google" {
  project = "project-720026ab-c9ef-46e8-839" # 【マスキング！】
  region  = "asia-northeast1"     # 東京リージョン
}

# GKEクラスタにアクセスするための認証情報を取得
data "google_client_config" "default" {}

# Kubernetesプロバイダの設定
provider "kubernetes" {
  # 作成したGKEクラスタのエンドポイント(URL)を指定
  host                   = "https://${google_container_cluster.primary.endpoint}"
  
  # Terraform実行時のGCPアクセストークンを使用
  token                  = data.google_client_config.default.access_token
  
  # GKEクラスタの証明書をデコードして指定
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# ネットワーク(VPC & Subnet)
resource "google_compute_network" "vpc_network" {
  name                    = "drf-vpc"
  auto_create_subnetworks = false # カスタムサブネットを使用するためfalse
}

resource "google_compute_subnetwork" "subnet" {
  name          = "drf-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = "asia-northeast1"
  network       = google_compute_network.vpc_network.id
}

# 外部通信(Cloud Router & Cloud NAT)
# ※Go CLIがSlackに通知を送るための出口
resource "google_compute_router" "router" {
  name    = "drf-router"
  region  = "asia-northeast1"
  network = google_compute_network.vpc_network.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "drf-nat"
  router                             = google_compute_router.router.name
  region                             = "asia-northeast1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# データベース接続 (Private Services Access)
# ※Cloud SQLをプライベートIPで繋ぐためのVPCピアリング設定
# Cloud SQLの実体は、ユーザーのVPCではなく「Googleが管理する別のVPC」の中に独立して作られる。
# そのため、ユーザーのVPCとGoogle側のVPCをPrivate Services AccessというVPCピアリングで
# 専用線のように繋ぐ必要がある。

resource "google_compute_global_address" "private_ip_address" {
  name          = "google-managed-services-drf-vpc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# データベース (Cloud SQL for PostgreSQL)
resource "google_sql_database_instance" "postgres" {
  name             = "drf-postgres-instance-v2" # *
  database_version = "POSTGRES_15"
  region           = "asia-northeast1"

  # 削除保護を無効化
  deletion_protection = false

  # VPCピアリングが完了してからDBを作成するよう明示
  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro" # ポートフォリオ用の最小構成
    ip_configuration {
      ipv4_enabled    = false # 【重要】パブリックIPを無効化
      private_network = google_compute_network.vpc_network.id
    }
  }
}

resource "google_sql_database" "database" {
  name     = "drf_db"
  instance = google_sql_database_instance.postgres.name
}

# DB用のランダムパスワードを自動生成
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?" # 一部のDBエンジンでパースエラーになりやすい記号(@や/など)を除外
}

# Cloud SQLユーザーの作成
resource "google_sql_user" "db_user" {
  name     = "drf-db-user"
  instance = google_sql_database_instance.postgres.name # 既存のインスタンス名(postgres)に合わせる
  password = random_password.db_password.result # resource "random_password" "db_password"で作成したもの
}

# Kubernetes Secretの作成
resource "kubernetes_secret" "django_db" {
  metadata {
    name      = "django-db-secret"
    namespace = "default"
  }

  data = {
    # 既存のgoogle_sql_database_instance.postgresからプライベートIPを取得
    DB_HOST = google_sql_database_instance.postgres.private_ip_address
    
    # PostgreSQLのデフォルトポート
    DB_PORT = "5432"
    
    # 上記で作成したユーザーのリソースから情報を取得
    DB_USER = google_sql_user.db_user.name
    DB_PASSWORD = google_sql_user.db_user.password
    
    # 既存のgoogle_sql_database.databaseからDB名を取得
    DB_NAME = google_sql_database.database.name
  }

  type = "Opaque"
}

# コンテナ基盤(GKEクラスター)
resource "google_container_cluster" "primary" {
  name     = "drf-gke-cluster"
  # ポートフォリオのコスト削減のため、リージョン(マルチゾーン)ではなく単一ゾーンを指定
  # asia-northeast1(リージョン全体)ではなくasia-northeast1-a(単一ゾーン)
  location = "asia-northeast1-a" 
  
  # 削除保護を無効化
  deletion_protection = false

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.subnet.id

  # プライベートクラスター設定(ノードにパブリックIPを持たせない)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # GitHub Actions等からアクセスするためマスターエンドポイントは公開
    # プライベートをfalseで公開する、の意
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "drf-node-pool"
  location   = "asia-northeast1-a"
  cluster    = google_container_cluster.primary.name
  node_count = 2 # 【ノード数定義】DRFのレプリカ数(2)に合わせて最低2つ。

  node_config {
    machine_type = "e2-small" # ポートフォリオ用の安価なインスタンス
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# Ingress用 静的IPアドレス
resource "google_compute_global_address" "static_ip" {
  # 【重要】マニフェスト(Ingress)の kubernetes.io/ingress.global-static-ip-name に指定した名前と完全に一致させること！
  name = "drf-api-static-ip" 
}

# コンテナレジストリ (Artifact Registry)
resource "google_artifact_registry_repository" "repo" {
  location      = "asia-northeast1"
  repository_id = "drf-repo"
  description   = "Docker repository for DRF and Go CLI"
  format        = "DOCKER"
}

# GKEからのArtifact Registryアクセス権限設定
# 1. 現在のプロジェクト情報を取得(プロジェクト番号を動的に得るため)
data "google_project" "project" {
  # providerブロックで指定しているものと同じプロジェクトID
  project_id = "project-720026ab-c9ef-46e8-839" 
}

# 2. デフォルトのCompute EngineサービスアカウントにArtifact Registry読み取り権限を付与
resource "google_artifact_registry_repository_iam_member" "compute_sa_ar_reader" {
  location   = google_artifact_registry_repository.repo.location
  repository = google_artifact_registry_repository.repo.name
  role       = "roles/artifactregistry.reader"
  
  # dataソースから取得したプロジェクト番号を使って、デフォルトSAを動的に指定
  member     = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Workload Identity Pool の作成
# (GitHubからのアクセスを受け入れる「箱」)
resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-actions-pool-v3" # *
  display_name              = "GitHub Actions Pool"
}

# Workload Identity Provider の作成
# (GitHub Actions専用の認証ルール)
# OIDC(Workload Identity)の設定
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider-v3" # *
  display_name                       = "GitHub Actions Provider"

  # GitHubから渡される情報(assertion)と、GCP側の属性(attribute)をマッピング
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "attribute.repository == 'HideTake761/Go-audit-Django-API-GKE'"

  # 認証の提供元がGitHubであることを指定
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# サービスアカウントとGitHubリポジトリの紐づけ
# (指定したリポジトリだけが、このサービスアカウントに変身できるようにする)
resource "google_service_account_iam_member" "github_actions_sa_binding" {
  # すでにTerraformで作ってあるサービスアカウントを指定
  service_account_id = "projects/project-720026ab-c9ef-46e8-839/serviceAccounts/terraform-sa@project-720026ab-c9ef-46e8-839.iam.gserviceaccount.com" # 【マスキング！】 
  
  # WIFを利用するための決まったロール
  role               = "roles/iam.workloadIdentityUser"
  
  # GitHubリポジトリからのアクセスのみを許可する設定
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/HideTake761/Go-audit-Django-API-GKE"
}
