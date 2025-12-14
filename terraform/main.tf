terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }

  required_version = ">= 0.13"
}

provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

# ==========================
#     Подготовка системы
# ==========================

resource "yandex_ydb_database_serverless" "db" {
  name      = "vvot05-cw2-db"
  folder_id = var.folder_id
  serverless_database {
    storage_size_limit = 1
  }
}

resource "yandex_iam_service_account" "sa" {
  name = "vvot05-cw2-sa"
}

resource "yandex_iam_service_account_static_access_key" "sa_static_key" {
  service_account_id = yandex_iam_service_account.sa.id
}

# ==========================
#      Назначение ролей
# ==========================

resource "yandex_resourcemanager_folder_iam_member" "kms_keys_encrypterDecrypter" {
  folder_id = var.folder_id
  role      = "kms.keys.encrypterDecrypter"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "lockbox_payloadViewer" {
  folder_id = var.folder_id
  role      = "lockbox.payloadViewer"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "ydb_editor" {
  folder_id = var.folder_id
  role      = "ydb.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "storage_uploader" {
  folder_id = var.folder_id
  role      = "storage.uploader"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "functions_functionInvoker" {
  folder_id = var.folder_id
  role      = "functions.functionInvoker"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "ymq_admin" {
  folder_id = var.folder_id
  role      = "ymq.admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = var.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

# ==========================
#     Создание секретов
# ==========================

resource "yandex_lockbox_secret" "secret" {
  name = "vvot05-cw2-secret"
}

resource "yandex_lockbox_secret_version" "secret_version" {
  secret_id = yandex_lockbox_secret.secret.id

  entries {
    key        = "AWS_ACCESS_KEY_ID"
    text_value = yandex_iam_service_account_static_access_key.sa_static_key.access_key
  }

  entries {
    key        = "AWS_SECRET_ACCESS_KEY"
    text_value = yandex_iam_service_account_static_access_key.sa_static_key.secret_key
  }
}

# ==========================
#   Создание таблицы в БД
# ==========================

resource "yandex_ydb_table" "docs-table" {
  path              = "docs"
  connection_string = yandex_ydb_database_serverless.db.ydb_full_endpoint

  column {
    name     = "id"
    type     = "Uuid"
    not_null = true
  }

  column {
    name     = "name"
    type     = "Utf8"
    not_null = true
  }

  column {
    name     = "url"
    type     = "Utf8"
    not_null = true
  }

  primary_key = ["id"]

  depends_on = [
    yandex_ydb_database_serverless.db,
    yandex_iam_service_account.sa,
    yandex_resourcemanager_folder_iam_member.ydb_editor
  ]
}

# ==========================
# Создание приватного бакета
# ==========================

resource "yandex_storage_bucket" "bucket" {
  bucket        = "vvot05-cw2-bucket"
  max_size      = 10e9
  folder_id     = var.folder_id
  force_destroy = true
}

# ==========================
# Создание очереди сообщений
# ==========================

resource "yandex_message_queue" "download_queue" {
  name                       = "vvot05-cw2-download-queue"
  message_retention_seconds  = 60 * 30
  visibility_timeout_seconds = 60 * 15

  access_key = yandex_iam_service_account_static_access_key.sa_static_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_static_key.secret_key

  depends_on = [
    yandex_resourcemanager_folder_iam_member.ymq_admin,
    yandex_iam_service_account_static_access_key.sa_static_key
  ]
}

data "yandex_message_queue" "download_queue_data" {
  name       = yandex_message_queue.download_queue.name
  access_key = yandex_iam_service_account_static_access_key.sa_static_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa_static_key.secret_key

  depends_on = [yandex_message_queue.download_queue]
}

# ============================
#       Создание функций
# ============================

data "archive_file" "handler_function_zip" {
  type        = "zip"
  output_path = "handler_function.zip"
  source_dir  = "../handler_function"
  excludes = [ ".env" ]
}

resource "yandex_function" "handler_function" {
  name               = "vvot05-cw2-handler-function"
  runtime            = "python312"
  entrypoint         = "index.handler"
  memory             = 1024
  execution_timeout  = 60 * 5
  service_account_id = yandex_iam_service_account.sa.id
  user_hash          = data.archive_file.handler_function_zip.output_sha256
  folder_id          = var.folder_id

  depends_on = [ data.archive_file.handler_function_zip ]

  content {
    zip_filename = data.archive_file.handler_function_zip.output_path
  }

  environment = {
    YDB_ENDPOINT = "grpcs://${yandex_ydb_database_serverless.db.ydb_api_endpoint}"
    YDB_DATABASE = yandex_ydb_database_serverless.db.database_path
    BUCKET_NAME  = yandex_storage_bucket.bucket.bucket
    ZONE         = var.zone
  }

  secrets {
    id                   = yandex_lockbox_secret.secret.id
    version_id           = yandex_lockbox_secret_version.secret_version.id
    key                  = "AWS_ACCESS_KEY_ID"
    environment_variable = "AWS_ACCESS_KEY_ID"
  }

  secrets {
    id                   = yandex_lockbox_secret.secret.id
    version_id           = yandex_lockbox_secret_version.secret_version.id
    key                  = "AWS_SECRET_ACCESS_KEY"
    environment_variable = "AWS_SECRET_ACCESS_KEY"
  }
}

data "archive_file" "scan_function_zip" {
  type        = "zip"
  output_path = "scan_function.zip"
  source_dir  = "../scan_function"
  excludes = [ ".env" ]
}

resource "yandex_function" "scan_function" {
  name               = "vvot05-cw2-scan-function"
  runtime            = "python312"
  entrypoint         = "index.handler"
  memory             = 512
  execution_timeout  = 60 * 1
  service_account_id = yandex_iam_service_account.sa.id
  user_hash          = data.archive_file.scan_function_zip.output_sha256
  folder_id          = var.folder_id

  depends_on = [ data.archive_file.scan_function_zip ]

  content {
    zip_filename = data.archive_file.scan_function_zip.output_path
  }

  environment = {
    YDB_ENDPOINT = "grpcs://${yandex_ydb_database_serverless.db.ydb_api_endpoint}"
    YDB_DATABASE = yandex_ydb_database_serverless.db.database_path
  }
}

# ============================
#      Создание триггера
# ============================

resource "yandex_function_trigger" "download_queue_trigger" {
  name      = "vvot05-cw2-download-queue-trigger"
  folder_id = var.folder_id

  message_queue {
    batch_cutoff       = 2
    queue_id           = yandex_message_queue.download_queue.arn
    service_account_id = yandex_iam_service_account.sa.id
    batch_size         = 1
  }

  function {
    id                 = yandex_function.handler_function.id
    service_account_id = yandex_iam_service_account.sa.id
  }

  depends_on = [
    yandex_message_queue.download_queue,
    yandex_function.handler_function
  ]
}

# ============================
#     Создание API-шлюза
# ============================

resource "yandex_api_gateway" "api_gw" {
  name              = "vvot05-cw2-api-gw"
  execution_timeout = "60"
  spec              = <<-EOT
openapi: 3.0.0
info:
  title: Sample API
  version: 1.0.0

paths:
  /upload:
    post:
      x-yc-apigateway-integration:
        type: cloud_ymq
        action: SendMessage
        queue_url: ${data.yandex_message_queue.download_queue_data.url}
        folder_id: ${var.folder_id}
        delay_seconds: 0
        payload_format_type: body
        service_account_id: ${yandex_iam_service_account.sa.id}

      responses:
        '202':
          description: Accepted
    
  /documents:
    get:
      x-yc-apigateway-integration:
        payload_format_version: '0.1'
        function_id: ${yandex_function.scan_function.id}
        tag: $latest
        type: cloud_functions
        service_account_id: ${yandex_iam_service_account.sa.id}
      
  /document/{key}:
    get:
      parameters:
        - name: key
          in: path
          required: true
          schema:
            type: string

      x-yc-apigateway-integration:
        type: object_storage
        bucket: ${yandex_storage_bucket.bucket.bucket}
        object: docs/{key}
        service_account_id: ${yandex_iam_service_account.sa.id}

      responses:
        '200':
          description: File download
EOT
}
