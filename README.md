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