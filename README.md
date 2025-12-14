<h2>Контрольная работа №2 по дисциплине "Введение в облачные технологии"</h2>
<h3>Имамов Нияз Флурович | группа 11-207</h3>

```shell
export YC_TOKEN=$(yc iam create-token)

export TF_VAR_cloud_id=<cloud_id>
export TF_VAR_folder_id=<folder_id>
export TF_VAR_zone=<prefix>
```

```shell
cd ./terraform
```

```shell
terraform init

terraform apply
```

```shell
terraform destroy
```

### Проверка API
```shell
export API_GW_URL=<api_gw_url>
```

```shell
curl -X POST https://$API_GW_URL/upload \
-H "Content-Type: application/json" \
-d '{"name": "example.pdf", "url": "https://raw.githubusercontent.com/NikoImam/vvot-cw2/main/files/example_1.pdf"}' -i
```

```shell
curl -X POST https://$API_GW_URL/upload \
-H "Content-Type: application/json" \
-d '{"name": "example.doc", "url": "https://raw.githubusercontent.com/NikoImam/vvot-cw2/main/files/example_2.doc"}' -i
```

```shell
curl https://$API_GW_URL/documents | jq
```

```shell
curl https://$API_GW_URL/document/<id> -OJ
```

---
**Ошибка интеграции YDB в API-Gateway**:
` {"message":"Unsupported API version \"\" for table \"/ru-central1/b1g71e95h51okii30p25/etnssrt38mqn0jvpl6dk/docs\""}  `