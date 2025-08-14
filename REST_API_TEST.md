- Add new item (POST)
$uri = 'http://localhost:8000/api/items/'
$body = @{
    product = 'Apple'
    price   = 180
} | ConvertTo-Json

Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body $body

- Extract a list of all items (GET)
$uri = 'http://localhost:8000/api/items/'

Invoke-RestMethod -Uri $uri -Method Get

- Extract a specific item (GET)
$uri = 'http://localhost:8000/api/items/?product=Apple'
Invoke-RestMethod -Uri $uri -Method Get

- Update a specific item (PUT)
$id = 1
$uri = "http://localhost:8000/api/items/$id/"
$body = @{
    product = 'Strawberry'
    price   = 500
} | ConvertTo-Json

Invoke-RestMethod -Uri $uri -Method Put -ContentType 'application/json' -Body $body

- Delete a specific item (DELETE)
$id = 1
$uri = "http://localhost:8000/api/items/$id/"

Invoke-RestMethod -Uri $uri -Method Delete
