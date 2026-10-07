# TestBlazorPythonApp

Blazor Web App (.NET 10), Python FastAPI service, and SQL Server.

```text
Browser -> Blazor server -> SQL Server
                        -> Python HTTP service -> the same SQL Server
```

Both applications save and read notes in the same database. SQL access stays on
the servers, not in the browser.

## Local development on Windows

Prerequisites: .NET 10 SDK, Python 3.12 or newer (64-bit), a running SQL Server
Developer/Express instance, `sqlcmd`, and Microsoft ODBC Driver 18 for SQL Server
(64-bit). Browser tests use Microsoft Edge.

Open this folder as the repository/workspace root. Restore dependencies:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\src\backend\requirements.txt -r .\tests\requirements.txt
dotnet restore .\src\blazor\BlazorApp.csproj
```

In the first PowerShell terminal:

```powershell
. .\scripts\configure-local.ps1
.\.venv\Scripts\python.exe -m uvicorn web_app:app --app-dir .\src\backend --host 127.0.0.1 --port 3200
```

In a second terminal:

```powershell
. .\scripts\configure-local.ps1
dotnet run --project .\src\blazor --launch-profile http
```

Open **http://localhost:5080**. Python API documentation is at
**http://127.0.0.1:3200/docs**.

The leading `. ` configures the current terminal. The script uses Windows
authentication and creates `BlazorLab` and `dbo.Notes` only if missing. It does not
delete existing notes or install/start/stop SQL Server. For a named instance, use
`. .\scripts\configure-local.ps1 -Server '.\SQLEXPRESS'` in each terminal.

With both services running, use a third terminal:

```powershell
. .\scripts\configure-local.ps1
.\.venv\Scripts\python.exe .\tests\test_local_stack.py -v
```

Tests cover both writers, cross-service reads, SQL persistence, input validation,
and browser buttons. They remove only their own notes. VS Code tasks provide
equivalent startup and test commands.

Press **Ctrl+C** in each application terminal to stop the services. SQL Server
remains running.

For a different database/authentication setup, configure `ConnectionStrings__Sql`
for .NET, `SQL_CONNECTION_STRING` (ODBC format) for Python, and optionally
`PythonService__BaseUrl`. Initialize the same table; do not run
`configure-local.ps1`, which selects local Windows authentication.

## Azure

Шаблон использует ту же структуру `infra/main.bicep`, `shared.bicep`,
`infra/app`, hooks, `azure.yaml` и `.github/workflows`, что оригинальный
React/Functions-шаблон. Вместо Functions/SWA публикуются два Linux Web App
на одном одноэкземплярном плане. Общие ресурсы не создаются и не изменяются.
Подготовка личного окружения: [AZURE-PERSONAL-SETUP.md](AZURE-PERSONAL-SETUP.md).

Blazor защищён Easy Auth/Entra; Python принимает только запросы из подсети
App Service. Оба приложения используют отдельные managed identities для SQL,
Blazor также читает секрет входа из Key Vault. В Azure остаётся
`ASPNETCORE_ENVIRONMENT=Production`: локальные `/api/*` не публикуются.
Application Insights получает разные service names для Blazor и Python.

### Однократная подготовка

Дополнительно к шагам личной настройки нужны Azure CLI, Azure Developer CLI
(`azd`) и PowerShell 7 (`pwsh`). Содержимое **этой папки**
`MyAppRepo\TestBlazorPythonApp` должно стать корнем GitHub-репозитория:
GitHub не запускает workflow, оставленный внутри вложенной папки.

Deploy identity нужны Contributor на группе приложения, Reader на общих
ресурсах/мониторинге и два действия на конкретной подсети `snet-webapps`:
`Microsoft.Network/virtualNetworks/subnets/join/action` для VNet integration и
`Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action`
для правила доступа к Python через service endpoint. Их назначает администратор
через ограниченную custom role; Reader сам по себе недостаточен.
Для GitHub Environment job не настроен: сохраняется OIDC subject ветки,
как в инструкции. Для `main` нужна отдельная federated credential.

Если роль `TestBlazorPythonApp Subnet Join` уже создана только с `join/action`,
администратор обновляет её под своей учётной записью в целевой подписке:

```powershell
.\scripts\update-subnet-deploy-role.ps1 -SubscriptionId "<subscription-id>"
```

Скрипт сохраняет ID роли, существующие права, scopes и назначения. После
распространения RBAC повтори GitHub **Deploy → Re-run failed jobs**;
пересоздавать ресурсы или добавлять deploy identity Owner на подписку не нужно.

**Важное отличие от оригинала:** `main.bicep` имеет scope `resourceGroup`,
а не `subscription`. Группа приложения должна уже существовать. Поэтому CI
не требует Contributor/Owner на подписку, не создаёт общие ресурсы, не выдаёт
RBAC-роли, не выполняет SQL-миграции и не изменяет Entra через Microsoft Graph.
Роли Key Vault, таблицу, SQL-пользователей и Web callback готовит администратор.

При уже выполненных шагах 1-11 повторно создавать SQL-пользователей не нужно.
Для нового окружения есть `database\azure-init.sql`: запускать в целевой
Azure SQL Database через разрешённую сеть под SQL Entra-администратором.
Пример для `sqlcmd` с Entra-аутентификацией:

```powershell
sqlcmd -S "tcp:<SQL_SERVER_FQDN>,1433" -d "<SQL_DATABASE_NAME>" -G -b `
  -i .\database\azure-init.sql `
  -v FrontendIdentityName="id-template-dev" BackendIdentityName="id-template-python-dev" `
     FrontendPrincipalId="<frontend-principal-id>" BackendPrincipalId="<backend-principal-id>"
```

Для новых identities их сначала создаёт администратор с именами из шаблона
(как в личной инструкции) либо выполняет первый provision после назначения
Key Vault роли. Principal IDs доступны также в outputs Bicep. В SQL нужны
**Principal/Object IDs**, а в connection strings используются **Client IDs**.
Скрипт выдаёт только SELECT/INSERT на `dbo.Notes`; пользователей с несовпадающим
SID не заменяет. Существующие роли из Portal не удаляет.

### Первый запуск в личном Azure

Работать из этой папки, не из родительского React-шаблона:

```powershell
Copy-Item .\infra\config.personal.example.json .\config.azure.json
# Заполнить config.azure.json фактическими значениями своего стенда.
.\scripts\configure-azure.ps1 -ConfigPath .\config.azure.json

az login --tenant $env:AZURE_TENANT_ID
az account set --subscription $env:AZURE_SUBSCRIPTION_ID
azd auth login --tenant-id $env:AZURE_TENANT_ID

azd provision --no-prompt
azd deploy backend --no-prompt
azd deploy frontend --no-prompt
```

Или `azd up` после настройки и входа. В конфигурации нет паролей:
секрет Entra остаётся в Key Vault. `config.azure.json` и `.azure` исключены
из Git. Не копируй корпоративные subscription/tenant IDs в личный профиль.
Настройка профиля ничего не разворачивает; hook останавливает provision при
несовпадении Azure CLI account и выбранного профиля.

Суффикс и имена должны соответствовать **уже созданным** ресурсам. Для личного
примера это `ar061026`, `dx-sql-ar061026-dev`, `dx-kv-ar061026-dev`,
`pe-sql-template-dev`. Не меняй APP_ID/суффикс после первого запуска, если не
хочешь создавать другие ресурсы. Повторный provision сохраняет имена identities
и одного плана; он управляет app settings целиком, поэтому дополнительные
настройки приложения нужно добавлять в Bicep, а не только в Portal.

Hook после provision проверяет разрешение Key Vault reference и печатает
`ENTRA_CALLBACK_URL`. В регистрации входа должен быть именно этот **Web**
redirect URI; hostname берётся у Azure, а не вычисляется по имени сайта.
Секрет регистрации имеет срок действия: его обновляет администратор в Entra
и в том же Key Vault secret. Hooks не генерируют и не печатают секреты.

Python публикуется исходниками с `requirements.txt`, зависимости собирает
Oryx; Windows virtualenv в пакет не входит. Поддерживаемые Python Linux images
содержат msodbcsql18. `azure_startup.py` проверяет наличие Driver 18 и обязательных
настроек: отсутствие драйвера даёт явную ошибку, а не незаметный переход на
другую аутентификацию. Не исправляй это открытием SQL firewall.

### GitHub Actions

Для ветки `dev` используются подготовленные repository secrets
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
Дополнительно создай repository variable **`AZURE_CONFIG_JSON`**:
вставь весь заполненный `config.azure.json`. Это идентификаторы/имена, не секрет
входа. Subscription/tenant в JSON должны совпадать с secrets.

Для `main` отдельно нужны secrets **`PROD_AZURE_CLIENT_ID`**,
**`PROD_AZURE_TENANT_ID`**, **`PROD_AZURE_SUBSCRIPTION_ID`** и variable
**`PROD_AZURE_CONFIG_JSON`** с `AZURE_ENV_NAME=template-prod`. Если они не
настроены, workflow завершится ошибкой **до Azure login**, не подставляя
личный/dev аккаунт. Ветки `dev` и `main` деплоятся автоматически;
`workflow_dispatch` принимает только эти ветки.

OIDC обеспечивает Azure login, но не доступ к частному SQL.
GitHub-hosted runner публикует код через отдельный SCM endpoint с Entra/RBAC,
не через публичный Python API. SCM не наследует ограничения главного сайта,
basic publishing authentication/FTP выключены. При корпоративном запрете
публичного SCM нужен runner с разрешённым сетевым доступом и соответствующие
SCM-правила; здесь не создаётся обход этих ограничений.

### Проверка после публикации

Проверка закрытия анонимного доступа выполняется после публикации **Blazor**,
а не между публикациями Python и Blazor. Она **не доказывает работу базы**
или успешный запуск Python. Actions отдельно выводит шаги `Python startup logs`
и `Blazor startup logs`, включая случаи неудачного деплоя. Ошибка чтения логов
помечается предупреждением и не заменяет результат деплоя.
Для реальной проверки войди через браузер тестовым пользователем:

```powershell
$env:APP_WEB_URL = azd env get-value APP_WEB_URL
$env:APP_API_URL = azd env get-value APP_API_URL
.\.venv\Scripts\python.exe .\tests\test_azure_stack.py --login
.\.venv\Scripts\python.exe .\tests\test_azure_stack.py
```

На Windows используется Edge; на Linux предварительно установи Chromium
через `python -m playwright install chromium`. Тест проверяет redirect на Entra,
публичный Python `403`, SQL health, обе кнопки записи, оба читателя и сохранность
после перезагрузки страницы. Он оставляет две уникальные `Azure smoke` записи
для проверки; другие данные не изменяет. После Restart обоих Web App повтори
тест и проверь сохранность прежних записей.
Файл `.local\azure.auth.json` содержит credentials браузера: не передавай
его коллегам, не загружай в CI и удали после проверки.

Проверь `appi-dx-core` после запросов: роли `${AZURE_ENV_NAME}-blazor` и
`${AZURE_ENV_NAME}-python`; SQL public access остаётся Disabled. Для бесплатной
serverless SQL первый доступ может ждать запуска базы; Always On/посещения
и telemetry расходуют ресурсы. Платные availability tests не создаются.

### Перенос в корпоративный Azure

Передавай содержимое этой папки без `.azure`, `.venv`, `config.azure.json`,
`bin/obj` и auth state. **Исходники, Bicep, azure.yaml и workflow менять
для смены аккаунта не нужно.** Администратор заполняет тот же JSON и GitHub
settings корпоративными значениями, подтверждает общие ресурсы и доступ.

Обычно меняются subscription/tenant/login client IDs, SQL/Key Vault/VNet names,
регион и уникальный суффикс. Если мониторинг в management-подписке, добавляется
`MONITORING_SUBSCRIPTION_ID`; если общие ресурсы в другой подписке,
`SHARED_SUBSCRIPTION_ID`. По умолчанию обе совпадают с подпиской приложения.
Поддерживаются также `SHARED_RESOURCE_GROUP`, `MONITORING_RESOURCE_GROUP`,
`APP_INSIGHTS_NAME`, `INTEGRATION_SUBNET_NAME`, `APP_SERVICE_PLAN_SKU`
и `PYTHON_VERSION` (`3.12`/`3.13`). Нужны делегация App Service, service endpoint
Microsoft.Web, private DNS/SQL, SQL-пользователи, роль Key Vault и Entra callback.

Это переносимость **одинаковой архитектуры**, не обещание автоматической
совместимости с любой корпоративной политикой. Исходные APIM/App Gateway
не переносятся: React SPA и Blazor Server имеют разные маршруты/WebSockets.
Если корпоративный шлюз, private SCM или service-to-service Entra tokens
обязательны, это отдельное согласованное изменение и отдельная облачная проверка.
Ограничение Python подсетью доверяет всем приложениям этой подсети, не только
identity Blazor. Общий B1-план подходит для первого стенда, не гарантирует
ёмкость для произвольного production-нагрузочного профиля.

## Initial GitHub upload

Run from this folder. If Git is not initialized yet, first run `git init -b dev`.
Then, after reviewing the files:

```powershell
git add .
git commit -m "Add Blazor and Python application"
git remote add origin https://github.com/AlexGoOn/TestBlazorPythonApp.git
git push -u origin dev
```

These commands assume the remote is not configured yet and its `dev` branch has
no conflicting history. Do not force-push over existing work.
