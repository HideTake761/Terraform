# ベースとなる公式のPythonイメージを指定
FROM python:3.13-slim

# 以下2つは、Dockerコンテナのオペレーティングシステム(OS)レベルで環境変数を設定するもの
# 環境変数を設定(Pythonのバッファリングを無効にして、ログがすぐに見えるようにする)
ENV PYTHONDONTWRITEBYTECODE 1
# Pythonが.pycというキャッシュファイルを作成するのを防ぐ
ENV PYTHONUNBUFFERED 1
# Pythonの出力(ログなど)をすぐに表示させる

# コンテナ内での作業ディレクトリを設定
WORKDIR /app

# 依存関係ファイルをコピーして、先にインストールする
# (コード変更のたびに再インストールが走らないようにするため)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# --no-cache-dir:pipがパッケージをインストールした際のキャッシュを残さないようにする
# -r:そのあとにあるファイル(requirements.txt)に書かれたパッケージをすべてインストールする

# プロジェクトの全ファイルをコンテナの作業ディレクトリにコピー
COPY . .

# Djangoが使用するポートを公開
EXPOSE 8000

# コンテナ起動時に実行するデフォルトコマンド
# 0.0.0.0 を指定することで、コンテナの外部からアクセス可能にする
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
