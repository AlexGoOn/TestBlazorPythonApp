# Личный Azure: Blazor + Python + SQL, пошаговая подготовка

Дата проверки документации: 6 октября 2026 года.

Это инструкция для личного учебного окружения: два Web App на одном Linux
App Service Plan B1, одна Azure SQL Database, частное подключение к базе,
вход через Entra и подготовка доступа GitHub Actions.

**Это не инструкция по запуску текущего Bicep без изменений.** Сейчас Bicep,
`azure.yaml` и workflow всё ещё разворачивают корпоративный React/Functions-сценарий.
Следующие шаги создают личную инфраструктуру вручную и фиксируют значения для
будущей адаптации. Не запускай старый `azd up`, `azd provision` или
`infra\setup-deploy-identity.sh` для этого стенда.

## Что получится

```text
Пользователь
    |
    +--> Entra: вход в сайт
    |
    +--> Web App: Blazor
              |
              +--> Web App: Python / FastAPI
              |
              +--> SQL Database

Python тоже обращается к той же SQL Database.
Оба Web App работают на одном Linux B1-плане.
Оба подключены к VNet для доступа к частному адресу SQL.
Python принимает запросы только из выделенной подсети приложений.
```

VNet — частная сеть. Подсеть — участок этой сети. Private Endpoint — частная
«дверь» к SQL. DNS переводит имя SQL-сервера в адрес этой двери.

В этой инструкции вход в Blazor защищает **App Service Authentication / Easy Auth**.
Это проверка на стороне Azure перед приложением. Она отличается от входа,
реализованного в коде через Microsoft.Identity.Web: второй механизм параллельно
не настраиваем. Текущий Blazor-код пока не отображает профиль пользователя.

## Имена: что можно повторить, а что нельзя

**Имя подписки не используется кодом: используется её Subscription ID.**
Переименование личной подписки в «sandbox» не заменяет корпоративный ID.
Получить в личном аккаунте тот же ID подписки или Tenant ID нельзя.

Resource groups и VNet можно назвать как в шаблоне. Имена SQL-сервера, Key Vault
и Web App должны быть доступны глобально. Корпоративные имена могут быть заняты.

В примерах уникальный суффикс — `ar061026`. Перед началом выбери свой, из
латинских букв нижнего регистра и цифр. Если имя занято, измени суффикс
**во всех соответствующих именах**, а не только в одном поле.

| Ресурс | Вводимое имя | Соответствие текущему шаблону |
|---|---|---|
| App ID | `template` | Уже задан в шаблоне |
| Окружение | `template-dev` | Уже используется для ветки `dev` |
| Общая resource group | `rg-shared` | Совпадает |
| Resource group приложения | `rg-template-dev` | Совпадает с формулой в `main.bicep` |
| Resource group мониторинга | `rg-dx-monitoring` | Совпадает |
| VNet | `dx-internal-vnet-dev` | Совпадает |
| Подсеть приложений | `snet-webapps` | Новая для App Service, не Functions |
| Подсеть частных подключений | `snet-private-endpoints` | Новая |
| SQL logical server | `dx-sql-ar061026-dev` | Вместо глобального `dx-sql-dev` |
| SQL Database | `BlazorLab` | Совпадает с локальной базой |
| SQL Private Endpoint | `pe-sql-template-dev` | Новый |
| Private DNS zone | `privatelink.database.windows.net` | Стандартное имя Azure SQL |
| App Service Plan | `asp-template-dev` | Новый общий план |
| Blazor Web App | `app-template-ar061026-dev` | Новый, вместо React/Functions |
| Python Web App | `app-template-python-ar061026-dev` | Новый |
| Identity Blazor | `id-template-dev` | Совпадает с именем identity в Bicep |
| Identity Python | `id-template-python-dev` | Новая отдельная identity |
| Key Vault | `dx-kv-ar061026-dev` | Вместо глобального `dx-keyvault-dev` |
| Log Analytics workspace | `log-dx-core-dev` | Новый |
| Application Insights | `appi-dx-core` | Совпадает |
| Action group | `ag-platform-dev` | Совпадает |
| Регистрация входа | `app-dxazure-template` | Совпадает |
| Секрет регистрации входа | `template-dev-entra-client-secret` | Совпадает |
| Identity деплоя GitHub | `dxazure-template-personal-deploy` | Новая, не общая корпоративная |

В дальнейшем эти различия будут передаваться параметрами Bicep. Одними именами
в Portal нельзя исправить корпоративные ID и старые типы ресурсов в коде.

Названия меню ниже приведены на английском. Чтобы повторять их буквально,
в Portal открой шестерёнку → **Language + region → Language: English → Apply**.
Интерфейс постепенно обновляется; иногда нужный раздел находится через поиск
в меню конкретного ресурса.

## Шаг 1. Выбрать личную подписку, каталог и бюджет

1. Открой <https://portal.azure.com> и войди личной учётной записью.
2. В верхней строке поиска введи `Subscriptions` и открой результат.
3. Открой свою подписку. На странице **Overview** скопируй **Subscription ID**.
4. Запиши его как `PERSONAL_SUBSCRIPTION_ID`. Это значение будет другим,
   чем sandbox/production ID в репозитории.
5. В верхнем поиске введи `Microsoft Entra ID`.
6. Открой **Overview**, скопируй **Tenant ID**. Запиши как `PERSONAL_TENANT_ID`.
7. Если выбран корпоративный каталог, через меню учётной записи
   **Switch directory** переключись на каталог личной подписки.
8. Во всех дальнейших мастерах в поле **Subscription** выбирай именно эту
   личную подписку. Не выбирай корпоративные sandbox или production.

Не создавай дополнительный tenant без необходимости: используй каталог,
связанный с личной подпиской. Если нет прав на создание пользователей,
регистраций или назначений доступа, сначала реши вопрос с правами владельца
этого личного каталога/подписки; это не повод экспериментировать в корпоративном.

Для предупреждений о расходах:

1. Открой **Subscriptions → твоя подписка → Cost Management → Budgets**.
2. Нажми **Add**.
3. Name: `budget-template-dev`.
4. Reset period: `Monthly`.
5. Amount: свой допустимый месячный бюджет в валюте аккаунта.
6. На странице уведомлений добавь Actual alerts на `50`, `80` и `100` процентов,
   укажи свой email.
7. Нажми **Create**.

**Бюджет не останавливает ресурсы.** B1 оплачивается, пока существует план,
в том числе когда сайты остановлены. SQL Private Endpoint, Key Vault,
журналы и дополнительные проверки могут оплачиваться отдельно.
Бесплатный лимит SQL не делает весь стенд бесплатным.

## Шаг 2. Создать три resource groups

Для каждой из трёх групп:

1. Верхний поиск → `Resource groups`.
2. **Create**.
3. Subscription: твоя личная подписка.
4. Resource group: имя из таблицы ниже.
5. Region: `West US 3`.
6. **Review + create → Create**.

| Имя | Что здесь будет |
|---|---|
| `rg-shared` | VNet, SQL-сервер, SQL Private Endpoint, DNS, Key Vault |
| `rg-template-dev` | Общий B1-план, оба Web App, identities приложений |
| `rg-dx-monitoring` | Workspace, Application Insights, Action group |

Если `West US 3` недоступен для твоей подписки, выбери другой доступный регион
и последовательно используй его для VNet, плана и обоих Web App.
VNet integration требует совпадения региона сети и приложений.

Группа мониторинга будет в **этой же личной подписке**, а не в management-подписке,
которая сейчас указана в `shared.bicep`.

## Шаг 3. Создать VNet и две подсети

1. Верхний поиск → `Virtual networks → Create`.
2. В **Basics** заполни:

| Поле | Значение |
|---|---|
| Subscription | Личная подписка |
| Resource group | `rg-shared` |
| Name | `dx-internal-vnet-dev` |
| Region | `West US 3` |

3. В **Security** не включай Bastion, Azure Firewall или DDoS Protection plan.
   Для этого стенда они не нужны.
4. В **IP addresses** задай IPv4 address space `10.20.0.0/16`.
5. Удали автоматически предложенную подсеть `default`, если она мешает
   заданию следующих подсетей и ещё ничем не используется.
6. **Add subnet**:

| Поле | Подсеть Web App | Подсеть Private Endpoint |
|---|---|---|
| Name | `snet-webapps` | `snet-private-endpoints` |
| Starting address | `10.20.1.0` | `10.20.2.0` |
| Size | `/26` | `/24` |
| Итоговый диапазон | `10.20.1.0/26` | `10.20.2.0/24` |
| Subnet delegation | `Microsoft.Web/serverFarms` | `None` |
| Service endpoints | `Microsoft.Web` | Не добавлять |
| NAT gateway | `None` | `None` |
| Network security group | `None` для этого учебного стенда | `None` |
| Route table | `None` | `None` |

7. Сохрани каждую подсеть.
8. **Review + create → Create**.

Если delegation или service endpoints отсутствуют в мастере, после создания
открой **VNet → Settings → Subnets → snet-webapps**, установи их там и нажми **Save**.

Делегация выделяет подсеть для App Service. Service endpoint `Microsoft.Web`
понадобится для ограничения входящих запросов к Python в шаге 7.
Это не SQL Private Endpoint: у SQL будет собственная частная «дверь».

Не помещай SQL Private Endpoint в `snet-webapps`.
Не создавай NAT Gateway, VPN Gateway, виртуальную машину или Docker для этих шагов.

## Шаг 4. Создать SQL-сервер и базу

Начни с бесплатного предложения базы, а не с SQL Server на виртуальной машине:

1. Открой <https://aka.ms/azuresqlhub>.
2. В **Create a database** нажми **Start free**.
3. Убедись, что мастер показывает **Free offer applied**.
4. Заполни:

| Поле | Значение |
|---|---|
| Subscription | Личная подписка |
| Resource group | `rg-shared` |
| Database name | `BlazorLab` |
| Server | `Create new` |

5. В окне создания сервера:

| Поле | Значение |
|---|---|
| Server name | `dx-sql-ar061026-dev` |
| Location | `West US 3` |
| Authentication method | `Microsoft Entra-only authentication`, если доступно |
| Microsoft Entra administrator | `Set admin` → выбери свою учётную запись из личного каталога |

6. Не указывай приложение или GitHub identity администратором SQL.
7. Нажми **OK** и вернись к созданию базы.
8. В настройках бесплатного предложения оставь
   **Auto-pause the database until next month** при исчерпании бесплатного лимита.
9. Не выбирай **Continue using database for additional charges**.
10. Не включай elastic pool, failover group и другие дополнительные ресурсы.
11. Если предлагается SQL Defender как платная опция, не включай его автоматически
    для этого учебного стенда.
12. Проверь Cost summary: бесплатное предложение должно быть применено.
13. **Review + create → Create**.

Если Free offer отсутствует, не выбирай платный тариф наугад: проверь условия
предложения и стоимость выбранной конфигурации перед созданием.

После создания:

1. Верхний поиск → `SQL servers → dx-sql-ar061026-dev`.
2. В **Overview** скопируй **Server name**, например
   `dx-sql-ar061026-dev.database.windows.net`.
3. Проверь раздел **Microsoft Entra ID** / **Microsoft Entra admin**:
   администратор должен быть установлен.

Пока разреши административное подключение со своего компьютера:

1. SQL server → **Security → Networking → Public access**.
2. Public network access: **Selected networks**.
3. Нажми **Add your client IPv4 address** и сохрани правило только для своего IP.
4. **Allow Azure services and resources to access this server**: **No**.
5. **Save**.

Этот доступ временный: он нужен для создания таблицы и пользователей в шаге 8.
После этого публичное подключение к SQL выключим.

## Шаг 5. Создать SQL Private Endpoint и проверить DNS

1. SQL server → **Security → Networking → Private access**.
2. **Create a private endpoint**.
3. Заполни **Basics**:

| Поле | Значение |
|---|---|
| Subscription | Личная подписка |
| Resource group | `rg-shared` |
| Name | `pe-sql-template-dev` |
| Network interface name | `pe-sql-template-dev-nic` |
| Region | `West US 3` |

4. В **Resource**:

| Поле | Значение |
|---|---|
| Resource type | `Microsoft.Sql/servers` |
| Resource | `dx-sql-ar061026-dev` |
| Target subresource | `sqlServer` |

5. В **Virtual Network**:

| Поле | Значение |
|---|---|
| Virtual network | `dx-internal-vnet-dev` |
| Subnet | `snet-private-endpoints` |
| Private IP configuration | `Dynamically allocate IP address` |

6. В **DNS**:

| Поле | Значение |
|---|---|
| Integrate with private DNS zone | `Yes` |
| Private DNS zone | `privatelink.database.windows.net` |
| Resource group зоны, если предлагается выбор | `rg-shared` |

7. **Review + create → Create**.
8. На SQL-сервере проверь состояние Private endpoint connection: **Approved**.
9. Открой Private Endpoint → Network interface и запиши его Private IP.
   Он должен быть из `10.20.2.x`.
10. Верхний поиск → `Private DNS zones → privatelink.database.windows.net`.
11. В **Recordsets** должна быть A-запись `dx-sql-ar061026-dev` с этим Private IP.
12. В **Virtual network links** должна быть связь с `dx-internal-vnet-dev`.

Если связи нет: **Add**, Link name `link-dx-internal-vnet-dev`,
Virtual network `dx-internal-vnet-dev`, **Enable auto registration: Off**,
затем **OK/Create**.

В строках подключения используем **обычное имя**
`dx-sql-ar061026-dev.database.windows.net`.
Не используем IP и не подставляем `privatelink.database.windows.net`
в качестве SQL Server address.

Публичный доступ пока не выключай: сначала заверши SQL-команды шага 8.

## Шаг 6. Создать один B1-план и два Web App

### Общий план

1. Верхний поиск → `App Service plans → Create`.
2. Заполни:

| Поле | Значение |
|---|---|
| Subscription | Личная подписка |
| Resource group | `rg-template-dev` |
| Name | `asp-template-dev` |
| Operating System | `Linux` |
| Region | `West US 3` |
| Pricing tier | `Basic B1` |
| Zone redundancy | `Disabled`, если поле доступно |

3. **Review + create → Create**.
4. После создания проверь, что число экземпляров плана — `1`.
   Не увеличивай его для первого теста.

### Web App с Blazor

1. Верхний поиск → `App Services → Create → Web App`.
2. В **Basics**:

| Поле | Значение |
|---|---|
| Subscription | Личная подписка |
| Resource group | `rg-template-dev` |
| Name | `app-template-ar061026-dev` |
| Publish | `Code` |
| Runtime stack | `.NET 10` |
| Operating System | `Linux` |
| Region | `West US 3` |
| Linux Plan / App Service Plan | **Выбрать существующий `asp-template-dev`** |

3. Не выбирай создание нового плана.
4. Во вкладке **Deployment** оставь Continuous deployment выключенным:
   старый workflow пока нельзя использовать.
5. Не создавай новую Application Insights автоматически — подключим общую в шаге 9.
6. **Review + create → Create**.

Если `.NET 10` отсутствует в выбранном регионе, остановись на этом шаге:
проект сейчас использует `net10.0`, поэтому просто выбрать `.NET 8` нельзя.

### Web App с Python

Повтори создание Web App со следующими отличиями:

| Поле | Значение |
|---|---|
| Name | `app-template-python-ar061026-dev` |
| Runtime stack | `Python 3.13`; если недоступен, `Python 3.12` |
| Operating System | `Linux` |
| App Service Plan | **Тот же `asp-template-dev`** |

После создания открой **App Service plans → asp-template-dev → Apps**:
должны отображаться **оба** Web App. Это проверка того, что ты не приобрёл два плана.

В **Overview** каждого Web App скопируй **Default domain**:

| Обозначение для дальнейших шагов | Что записать |
|---|---|
| `BLAZOR_HOST` | Фактический Default domain Blazor |
| `PYTHON_HOST` | Фактический Default domain Python |

**Не вычисляй эти адреса по имени ресурса.** Azure может добавить уникальный
суффикс и регион в default hostname. Все callback URL и BaseUrl ниже должны
использовать фактические адреса из Overview.

Пока приложения не опубликованы, Azure показывает стандартную страницу.
Это нормально; ресурсы Web App ещё не содержат наш код.

## Шаг 7. Подключить оба приложения к сети и закрыть Python

### VNet integration — повторить для каждого Web App

1. Открой Web App → **Settings → Networking**.
2. В **Outbound traffic configuration** открой **Virtual network integration**.
3. **Add virtual network integration**.
4. Для первого приложения выбери:

| Поле | Значение |
|---|---|
| Subscription | Личная подписка |
| Virtual Network | `dx-internal-vnet-dev` |
| Subnet | `snet-webapps` |

5. **Connect**.
6. Для второго приложения выбери существующее подключение плана
   `dx-internal-vnet-dev/snet-webapps`, если Portal предлагает его.
7. В итоге у **обоих** приложений должно быть это VNet-подключение.

Не подключай их к `snet-private-endpoints`.
Не добавляй маршрутизацию через корпоративный firewall или NAT для этого стенда.
При стандартной сети частные адреса SQL доступны через VNet integration.

### Общие настройки

В каждом Web App → **Settings → Configuration → General settings**:

| Настройка | Blazor | Python |
|---|---|---|
| Always On | `On` | `On` |
| HTTPS Only | `On` | `On` |
| Minimum inbound TLS version | `1.2` или выше | `1.2` или выше |
| FTP state | `Disabled` | `Disabled` |
| Session affinity | `On` | Можно оставить `On` |
| Web sockets, если переключатель доступен | `On` | Не требуется |

Нажми **Save/Apply**. Для Linux отсутствие отдельного переключателя WebSockets
не означает отсутствие поддержки: после публикации проверим соединение Blazor.
Azure SignalR Service для первого одноэкземплярного стенда создавать не нужно.

У Python → **Configuration → Stack settings → Startup Command** введи:

```text
python -m uvicorn web_app:app --host 0.0.0.0 --port 8000
```

Это команда для Azure, а не локальный запуск с `127.0.0.1:3200`.
Она предполагает, что при публикации **содержимое `src\backend`** станет корнем
Python-приложения, и зависимости из его `requirements.txt` будут установлены.

### Входящие запросы к Python

Не оставляй изменяющий базу Python API открытым всему интернету.

1. Открой **Python Web App → Settings → Networking**.
2. В **Inbound traffic configuration** нажми **Public network access** /
   **Access restrictions**.
3. Public network access оставь **Enabled** / **Enabled from selected networks**,
   в зависимости от отображаемого интерфейса. Это схема service endpoint,
   а не полностью выключенный публичный endpoint.
4. Во вкладке правил главного сайта нажми **Add**.
5. Заполни:

| Поле | Значение |
|---|---|
| Name | `allow-blazor-subnet` |
| Action | `Allow` |
| Priority | `100` |
| Type | `Virtual Network` |
| Subscription | Личная подписка |
| Virtual network | `dx-internal-vnet-dev` |
| Subnet | `snet-webapps` |
| Ignore missing Microsoft.Web service endpoints | Не включать |

6. **Add rule**.
7. **Unmatched rule action: Deny**.
8. **Save**.
9. Убедись, что service endpoint `Microsoft.Web` включён у `snet-webapps`.

Это ограничивает доступ подсетью, а не единственным приложением по его identity.
Для учебного стенда здесь только наши приложения. Для более строгой корпоративной
схемы можно дополнительно проверять service-to-service токены.

У Blazor оставь публичный доступ включённым: вход пользователей защитим Entra.

В **Advanced tool site / SCM site** Python не включай **Use main site rules**
без плана доступа деплоя. SCM — отдельный адрес публикации и диагностической
консоли; если запретить его GitHub runner, деплой перестанет работать.
На первом этапе оставь независимые SCM-правила; доступ туда всё равно требует
авторизации Azure. В корпоративной схеме эти правила согласуются отдельно.

Обычное открытие `https://PYTHON_HOST/docs` из домашнего браузера теперь должно
давать `403`. Это ожидаемая защита, не ошибка сервиса. Blazor вызывает Python
по HTTPS через настроенную подсеть, **не по `localhost`**.

## Шаг 8. Создать две identities и выдать доступ внутри SQL

### Identity Blazor

1. Верхний поиск → `Managed Identities → Create`.
2. Subscription: личная подписка.
3. Resource group: `rg-template-dev`.
4. Region: `West US 3`.
5. Name: `id-template-dev`.
6. **Review + create → Create**.
7. Открой identity и запиши отдельно **Client ID**, **Principal ID / Object ID**
   и **Resource ID**. Это три разных значения.

Повтори для Python с именем `id-template-python-dev`.

### Прикрепить identities

1. Blazor Web App → **Settings → Identity → User assigned → Add**.
2. Выбери `id-template-dev` → **Add**.
3. Python Web App → **Settings → Identity → User assigned → Add**.
4. Выбери `id-template-python-dev` → **Add**.

Не прикрепляй identity GitHub Actions к работающим приложениям.

### Создать таблицу и SQL-пользователей

На своём компьютере открой SQL Server Management Studio:

| Поле | Значение |
|---|---|
| Server type | `Database Engine` |
| Server name | Фактическое `<SQL_SERVER>.database.windows.net` из шага 4 |
| Authentication | `Microsoft Entra MFA` / интерактивный Entra-вход |
| User | Entra-администратор SQL-сервера |
| Database в Connection properties | `BlazorLab` |
| Encrypt | Включено |
| Trust server certificate | Выключено |

Временное правило твоего IP из шага 4 должно ещё действовать.
Если домашний IP поменялся, обнови **только это** правило.

1. Подключись.
2. Выбери базу `BlazorLab` → **New Query**.
3. Открой в проекте `database\init.sql`.
4. Скопируй **только блок от `IF OBJECT_ID(N'dbo.Notes', N'U') IS NULL`
   до соответствующего `END;`**.
5. Выполни его в `BlazorLab`. Не выполняй здесь локальные `CREATE DATABASE`
   и `USE BlazorLab`: облачная база уже создана.
6. В той же базе выполни:

```sql
IF DATABASE_PRINCIPAL_ID(N'id-template-dev') IS NULL
    CREATE USER [id-template-dev] FROM EXTERNAL PROVIDER;

IF DATABASE_PRINCIPAL_ID(N'id-template-python-dev') IS NULL
    CREATE USER [id-template-python-dev] FROM EXTERNAL PROVIDER;

ALTER ROLE db_datareader ADD MEMBER [id-template-dev];
ALTER ROLE db_datawriter ADD MEMBER [id-template-dev];

ALTER ROLE db_datareader ADD MEMBER [id-template-python-dev];
ALTER ROLE db_datawriter ADD MEMBER [id-template-python-dev];
```

7. Проверь таблицу:

```sql
SELECT TOP (10) Id, Text, CreatedBy, CreatedAt FROM dbo.Notes;
```

На этом этапе пустой результат нормален. Оба приложения получают чтение и запись,
но не право менять схему или создавать другие базы.

Права Azure Contributor не заменяют этих SQL-пользователей. Полученный Entra-токен
тоже не даёт SQL-доступ автоматически.

### Закрыть публичный SQL

1. Вернись в **SQL server → Security → Networking → Public access**.
2. Установи **Public network access: Disabled**.
3. **Save**.
4. Убедись, что Private Endpoint всё ещё **Approved**.

SSMS с домашнего компьютера после этого не подключится. Доступ должен работать
из приложений, подключённых к VNet. Если понадобятся административные изменения,
можно временно повторить ограниченный доступ своего IP, выполнить их и снова
выключить публичный доступ. Не открывай базу всем ради удобства.

## Шаг 9. Создать Key Vault, мониторинг и настройки приложений

### Key Vault

1. Верхний поиск → `Key vaults → Create`.
2. Заполни:

| Поле | Значение |
|---|---|
| Subscription | Личная подписка |
| Resource group | `rg-shared` |
| Key vault name | `dx-kv-ar061026-dev` |
| Region | `West US 3` |
| Pricing tier | `Standard` |
| Permission model в Access configuration | `Azure role-based access control` |

3. Для этого стенда в Networking оставь публичный адрес доступным.
   Секреты всё равно защищены авторизацией; это не анонимный доступ.
4. Не включай Premium/HSM и не создавай дополнительные private endpoints на этом этапе.
5. **Review + create → Create**.

Назначь роли на **самом Key Vault**:

1. Key Vault → **Access control (IAM) → Add → Add role assignment**.
2. Role: `Key Vault Secrets Officer`.
3. Members: `User, group, or service principal → Select members` → твоя учётная запись.
4. **Review + assign**.
5. Повтори с Role `Key Vault Secrets User`.
6. Members: `Managed identity → Select members → User-assigned managed identity`.
7. Выбери `id-template-dev`.
8. **Review + assign**.

Python сейчас не читает секрет регистрации входа, поэтому роль на Key Vault
ему не выдаём без необходимости. SQL через managed identity не требует SQL-пароля.

Для Key Vault references нужно также выбрать user-assigned identity:
одного прикрепления к Web App недостаточно.

1. В Portal нажми **Cloud Shell** в верхней панели.
2. Выбери **PowerShell**. Если доступен режим без постоянного storage,
   используй его; отдельное хранилище Functions не требуется.
3. Подставь личный Subscription ID и выполни:

```powershell
az account set --subscription "09f8044f-9ae5-4de3-88c1-95cef11eb596"
$identityId = az identity show --resource-group rg-template-dev --name id-template-dev --query id -o tsv
az webapp update --resource-group rg-template-dev --name app-template-ar061026-dev --set "keyVaultReferenceIdentity=$identityId"
```

При выбранном другом суффиксе замени имя Web App. Эти команды не содержат секретов.

### Мониторинг

Через верхний поиск создавай ресурсы по очереди:

| Ресурс и меню | Поля |
|---|---|
| `Log Analytics workspaces → Create` | Subscription: личная; Resource group: `rg-dx-monitoring`; Name: `log-dx-core-dev`; Region: `West US 3` |
| `Application Insights → Create` | Subscription: личная; Resource group: `rg-dx-monitoring`; Name: `appi-dx-core`; Region: `West US 3`; Workspace: созданный `log-dx-core-dev` |
| `Monitor → Alerts → Action groups → Create` | Resource group: `rg-shared`; Name: `ag-platform-dev`; Display name: `platformdev`; Region: `Global`, если предлагается |

В Action group → **Notifications**:

1. Notification type: `Email/SMS message/Push/Voice`.
2. Name: `owner-email`.
3. Включи только **Email**, введи свой email.
4. **OK → Review + create → Create**.

Платные Standard availability tests пока не создавай. Если Python закрыт правилами
подсети, обычные внешние проверки не смогут обращаться к нему напрямую.

В Application Insights → **Overview** скопируй **Connection String**.
Создание этого ресурса ещё не включает телеметрию в приложениях: SDK/настройки
сбора нужно адаптировать отдельно.

### Переменные Blazor

Web App Blazor → **Settings → Environment variables → App settings → Add**.
Добавляй имя и значение, после всех изменений нажми **Apply**.

| Name | Value |
|---|---|
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `PythonService__BaseUrl` | `https://<PYTHON_HOST>/` с фактическим hostname |
| `ConnectionStrings__Sql` | Строка ниже с SQL hostname и Client ID identity Blazor |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Connection String из `appi-dx-core` |

```text
Server=tcp:dx-sql-ar061026-dev.database.windows.net,1433;Database=pe-sql-template-dev;Authentication=Active Directory Managed Identity;User Id=864dfdf8-4ae6-4bd3-9ecf-1b1977c6c158;Encrypt=True;TrustServerCertificate=False;
```

### Переменные Python

Python Web App → тот же раздел **Environment variables → App settings**:

| Name | Value |
|---|---|
| `SQL_CONNECTION_STRING` | Строка ниже с Client ID identity Python |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | `true` |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Connection String из `appi-dx-core` |

```text
Driver={ODBC Driver 18 for SQL Server};Server=tcp:dx-sql-ar061026-dev.database.windows.net,1433;Database=pe-sql-template-dev;Authentication=ActiveDirectoryMsi;UID=7b33399b-1a96-4fb2-8218-eb2ca22f5186;Encrypt=yes;TrustServerCertificate=no;
```

Здесь используются **Client ID**, не Principal ID и не Client ID регистрации входа.
Двойное подчёркивание в .NET-переменных обязательно.
Не копируй облаку `Integrated Security=True` или `Trusted_Connection=yes`
из локального Windows-запуска.

**Оставшийся prerequisite кода:** текущий Blazor использует
`Microsoft.Data.SqlClient 7.1.1`, но ещё не содержит
`Microsoft.Data.SqlClient.Extensions.Azure`. Для указанного managed identity
режима нужен Azure extension совместимой версии; по документации он регистрирует
провайдеры автоматически. Это нужно добавить и проверить перед облачным деплоем,
а не пытаться исправить отсутствующий пакет действиями в Portal.

Python умеет использовать этот режим через ODBC, но в Linux-среде Web App
должен быть установлен соответствующий **системный ODBC Driver**:
установка `pyodbc` через pip сама драйвер не устанавливает.
Наличие Driver 18 нужно проверить после публикации в SSH-консоли приложения:

```text
python -c "import pyodbc; print(pyodbc.drivers())"
```

Команду выполняй в Python-окружении опубликованного приложения. Если нужного
драйвера нет, это задача настройки runtime/деплоя, а не настройки SQL firewall.
Не считай успешную установку Python-зависимостей доказательством наличия драйвера.

## Шаг 10. Настроить тестового пользователя и вход через Entra

### Пользователь

1. Верхний поиск → `Microsoft Entra ID → Users → New user → Create new user`.
2. User principal name: `tester`.
3. Domain: домен своего каталога `<твой-каталог>.onmicrosoft.com`.
4. Display name: `Template tester`.
5. Account enabled: `Yes`.
6. Password: сгенерированный или свой, сохранить вне репозитория.
7. **Review + create → Create**.

Пользователю не нужны Azure Contributor/Owner. Он будет посетителем сайта,
а не администратором инфраструктуры.

### Регистрация приложения

1. Entra → **App registrations → New registration**.
2. Name: `app-dxazure-template`.
3. Supported account types:
   **Accounts in this organizational directory only (Single tenant)**.
4. Redirect URI platform: **Web**.
5. Redirect URI:

```text
https://<BLAZOR_HOST>/.auth/login/aad/callback
```

6. **Register**.
7. В Overview запиши **Application (client) ID** как `LOGIN_CLIENT_ID`.
8. Проверь **Directory (tenant) ID**: это личный tenant.
9. **Certificates & secrets → Client secrets → New client secret**.
10. Description: `template-dev-entra-client-secret`.
11. Expiration: например `6 months`.
12. **Add**.
13. Скопируй **Value**, не Secret ID. Значение показывается один раз.

Сохрани его в Key Vault:

1. Key Vault `dx-kv-ar061026-dev` → **Objects → Secrets → Generate/Import**.
2. Upload options: `Manual`.
3. Name: `template-dev-entra-client-secret`.
4. Secret value: скопированное значение.
5. **Create**.

Если видишь Forbidden после назначения роли, дождись распространения прав
и повтори запрос. Не меняй модель доступа на более широкую ради обхода ошибки.

### Включить App Service Authentication у Blazor

1. Blazor Web App → **Settings → Authentication → Add identity provider**.
2. Identity provider: `Microsoft`.
3. Tenant configuration: **Workforce configuration (current tenant)**.
4. App registration: **Pick an existing app registration in this directory**.
5. Выбери `app-dxazure-template`.
6. Если мастер предлагает ручной ввод данных:

| Поле | Значение |
|---|---|
| Application/client ID | `LOGIN_CLIENT_ID` |
| Client secret | Значение созданного секрета |
| Issuer URL | `https://login.microsoftonline.com/<PERSONAL_TENANT_ID>/v2.0` |

7. Restrict access: **Require authentication**.
8. Unauthenticated requests: **HTTP 302 Found redirect** / redirect to Microsoft.
9. Require HTTPS: `Yes`.
10. Token store: можно оставить включённым.
11. **Add/Save**.
12. Проверь callback URI регистрации и tenant/issuer в созданном провайдере.
13. Если включена проверка allowed token audiences, используй Client ID этой
    регистрации; не Client ID managed identity или GitHub.

Затем открой Blazor → **Environment variables** и найди настройку client secret
провайдера. Обычно это `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`;
точное имя также видно в настройках Authentication.

Замени её значение на:

```text
@Microsoft.KeyVault(SecretUri=https://dx-kv-ar061026-dev.vault.azure.net/secrets/template-dev-entra-client-secret)
```

Нажми **Apply**. Проверь статус Key Vault reference: секрет должен успешно
разрешаться. Важны и роль `Key Vault Secrets User`, и `keyVaultReferenceIdentity`
из шага 9.

Это **не** SPA-вход старого React и **не** callback `/signin-oidc` из варианта
Microsoft.Identity.Web. Не смешивай адреса разных механизмов.
Старый `postdeploy.sh`, обновляющий `spa.redirectUris`, сюда не подходит.

В Python браузерный вход через Entra не включай: Blazor вызывает его как сервис
без пользовательской cookie. В этой учебной схеме Python защищён сетью из шага 7.
Если включить ему Require authentication без добавления service-to-service токенов
в код Blazor, текущий HTTP-клиент перестанет работать.

Этот шаг проверяет вход на сайт. Он не восстанавливает сам по себе старый
Python `/user` с Graph/OBO: такой функции у нового минимального приложения
пока нет.

## Шаг 11. Подготовить OIDC GitHub без корпоративных прав

Это подготовка на будущее. В отдельном `MyAppRepo` workflow пока нет.
Старый `.github\workflows\deploy.yml` остался в родительском Azure-шаблоне:
не копируй и **не включай** его.

В личном GitHub-репозитории:

1. Открой **Actions → Deploy → меню с тремя точками → Disable workflow**,
   если старый workflow уже присутствует.
2. Используй личный репозиторий, не корпоративный. Загружай содержимое
   `MyAppRepo`, а не родительскую папку Azure-шаблона. Команды первой загрузки
   приведены в `README.md` рядом с этой инструкцией.
3. Подготовь ветку `dev`.

В Azure:

1. **Microsoft Entra ID → App registrations → New registration**.
2. Name: `dxazure-template-personal-deploy`.
3. Account type: `Single tenant`.
4. Redirect URI: не задавать.
5. **Register**.
6. Запиши Application/client ID как `DEPLOY_CLIENT_ID`.
7. **Certificates & secrets → Federated credentials → Add credential**.
8. Federated credential scenario:
   **GitHub Actions deploying Azure resources**.
9. Заполни:

| Поле | Значение |
|---|---|
| Organization | Твой GitHub login / личная организация |
| Repository | Имя твоего личного репозитория |
| Entity type | `Branch` |
| GitHub branch name | `dev` |
| Name | `github-dev` |
| Audience, если отображается | `api://AzureADTokenExchange` |

10. **Add**.

Для обычного subject ветки связь выглядит как
`repo:<owner>/<repo>:ref:refs/heads/dev`. Если GitHub настроен на custom OIDC subject
или ID-qualified subject, он должен совпадать с фактически выдаваемым subject.
Корпоративную строку с `DevExpress` и numeric IDs не копируй.
Если будущий job использует GitHub Environment, вместо Branch нужна привязка
к этому Environment.

### Назначения доступа

1. **Resource groups → rg-template-dev → Access control (IAM)**.
2. **Add role assignment → Contributor**.
3. Members: **User, group, or service principal → Select members**.
4. Найди `dxazure-template-personal-deploy`.
5. **Review + assign**.
6. На `rg-shared` аналогично назначь только **Reader**.
7. На `rg-dx-monitoring` назначь **Reader**, если будущий деплой читает её ресурсы.

Этого достаточно не для любого Bicep, а для ограниченного сценария:
общая сеть, роли, SQL-пользователи и регистрации заранее настроены администратором.
Если будущий Bicep повторно назначает VNet integration, ему дополнительно
понадобятся права чтения/join нужной подсети. Если он меняет общую инфраструктуру,
потребуются соответствующие отдельные права. Их нужно определить при адаптации,
а не выдавать заранее Owner всей подписки.

Не назначай этому deploy identity:

- Owner или Contributor на всю подписку;
- Role Based Access Control Administrator на всю подписку;
- Microsoft Graph `Application.ReadWrite.All`.

Роли приложений на Key Vault и пользователей SQL уже назначил ты, а не workflow.
Contributor группы позволяет менять и удалять собственные ресурсы приложения,
поэтому это ограничение радиуса ошибки, не запрет на любые ошибки.

В GitHub → **Settings → Secrets and variables → Actions** подготовь:

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | `DEPLOY_CLIENT_ID` |
| `AZURE_TENANT_ID` | `PERSONAL_TENANT_ID` |
| `AZURE_SUBSCRIPTION_ID` | `PERSONAL_SUBSCRIPTION_ID` |

Можно хранить их как repository secrets; это идентификаторы, не SQL-пароль.
Их добавление **не переопределяет** hardcoded env в существующем `deploy.yml`.
При адаптации workflow должен явно читать эти значения.

## Шаг 12. Зафиксировать настройки и проверить после адаптации деплоя

### Что уже подготовлено

После шагов 1–11 в Portal есть сеть, база, DNS, два пустых Web App на одном плане,
identities, SQL-права, Key Vault, мониторинг, Entra-вход и доверие GitHub.

**Полный облачный запуск ещё не проверен.** В рамках этой инструкции код и Bicep
не изменяются. Перед публикацией необходимо:

| Что адаптировать | Зачем |
|---|---|
| Bicep из родительского шаблона, если нужен IaC | Адаптировать до переноса: один Linux B1-план, два Web App, личные IDs, SQL/Key Vault и подсеть |
| `azure.yaml`, если нужен azd | Добавить конфигурацию .NET/App Service и Python/App Service; старый файл не переносился |
| `.github\workflows\deploy.yml` | Создать для двух Web App с личными OIDC-параметрами; старый workflow не переносился |
| Entra hooks | Не создавать SPA redirect URI и не раздавать Graph-права для этой схемы |
| .NET SQL dependencies | Добавить Azure extension для managed identity |
| Python runtime | Проверить системный ODBC Driver и установку зависимостей |
| Телеметрия | Подключить сбор .NET/Python, а не только создать Application Insights |
| Миграции базы | Запуск из разрешённой сети или отдельно администратором |

Обычный GitHub-hosted runner не находится в твоей VNet.
Azure login позволяет ему управлять Azure, но не подключает его к частному SQL.
Публиковать код в Web App он сможет при доступном SCM; выполнять SQL-миграции
через закрытый сервер — нет без отдельной сетевой схемы.

При будущем деплое должны публиковаться:

- результат `dotnet publish` проекта `src\blazor`;
- содержимое `src\backend` с `web_app.py` и `requirements.txt` в корне Python-пакета,
  без Windows `.venv`/`backend_env`.

### Проверки после публикации

| Проверка | Как и что должно получиться |
|---|---|
| Один оплачиваемый план | `asp-template-dev → Apps`: оба приложения; экземпляров плана `1` |
| Вход | Открыть `https://<BLAZOR_HOST>/` в приватном окне; увидеть вход Microsoft, войти `tester@...` |
| Запись из Blazor | Save with Blazor: запись появляется в обоих списках |
| Запись через Python | Save with Python: запись появляется в обоих списках |
| Python закрыт | `https://<PYTHON_HOST>/docs` с домашнего компьютера возвращает `403` |
| SQL закрыт публично | SQL Public network access `Disabled`, но обе кнопки работают |
| DNS | Из среды Web App имя SQL разрешается в IP SQL Private Endpoint |
| Key Vault | Client-secret reference в Blazor имеет успешный статус |
| Перезапуск | После Restart обоих Web App записи остаются |
| Телеметрия | После настройки SDK запросы/ошибки видны в `appi-dx-core` с различимыми именами сервисов |
| Повторный деплой | Не создаёт второй план, новые identities или дублирующиеся регистрации |

Проверку DNS выполняй **из Web App**, не с домашнего компьютера и не из обычного
Cloud Shell. В SSH-консоли Python-приложения можно использовать:

```text
python -c "import socket; print(socket.gethostbyname('dx-sql-ar061026-dev.database.windows.net'))"
```

Сравни результат с Private IP из шага 5.
Если имя разрешается в публичный IP, проверяй VNet integration и link DNS-зоны.
Если IP частный, но вход в SQL запрещён, проверяй выбранную identity и SQL-пользователя.

В Azure оставь `ASPNETCORE_ENVIRONMENT=Production`: локальные .NET endpoints
`/api/notes` и `/api/python/notes` намеренно выключены в production.
Это не поломка сайта. Локальный `tests\test_local_stack.py` нельзя целиком запускать
против этого защищённого облачного стенда без адаптации.

**Always On и бесплатный SQL:** текущая главная страница Blazor читает базу.
Прогрев, посещения и проверки здоровья могут поддерживать SQL активным и расходовать
бесплатные vCore-секунды. Always On не гарантирует бесплатную базу.
При выбранном безопасном режиме база остановится после исчерпания лимита,
и приложение будет показывать ошибки подключения до его обновления.

### Значения, которые нужно сохранить вне репозитория

Не записывай пароли и client secrets в этот документ. Идентификаторы удобно
сохранить в своих настройках окружения:

| Значение | Где взять |
|---|---|
| Personal Subscription ID | Subscriptions → Overview |
| Personal Tenant ID | Entra → Overview |
| Region | Выбранный общий регион |
| Фактический уникальный суффикс | Твой выбор вместо `ar061026` |
| SQL Server FQDN | SQL server → Overview |
| SQL Database | `BlazorLab` |
| VNet/subnet resource ID | VNet/subnet → Properties/JSON View |
| BLAZOR_HOST / PYTHON_HOST | Web App → Overview → Default domain |
| Client ID и Resource ID обеих managed identities | Managed Identities → Overview/Properties |
| LOGIN_CLIENT_ID | Регистрация `app-dxazure-template` → Overview |
| DEPLOY_CLIENT_ID | Регистрация `dxazure-template-personal-deploy` → Overview |
| Key Vault URI | Key Vault → Overview |
| App Insights resource ID и Connection String | Application Insights → Overview/Properties |
| Action group resource ID | Action group → Properties/JSON View |

### Перед переносом в корпоративное окружение

Один и тот же код/Bicep должен получать **разные параметры**, а не одинаковые ID.
У администратора нужно подтвердить:

- Linux App Service Plan: общий ли он для обоих приложений, достаточно ли ресурсов;
- подсеть для App Service с правильной делегацией, а не подсеть старого Functions;
- SQL Private Endpoint, DNS и сетевые ограничения;
- отдельную базу и SQL-пользователей identities обоих приложений;
- доступ к корпоративному Key Vault и выбранную модель входа Entra;
- способ защиты Python и правила SCM/деплоя;
- необходимость APIM/Application Gateway, если они обязательны корпоративно;
- способ выполнения миграций в закрытой сети.

APIM, Application Gateway, Cosmos DB, Functions, Static Web Apps, Functions Storage,
ADLS и AI-сервис **в этом личном сценарии не создаём**.
Если корпоративный шлюз обязателен, его маршруты, авторизацию и WebSocket-путь
Blazor нужно тестировать отдельно: личный стенд без шлюза этого не доказывает.

Ручная подготовка помогает понять Azure. Чтобы деплой стал воспроизводимым,
после неё нужно перенести необходимые настройки в Bicep и проверить создание
нового окружения без ручных исправлений. Для Bicep этого репозитория используются
Azure Verified Modules; имена вложенных deployments должны отличаться.

## Как остановить расходы

Остановка Web App не прекращает оплату B1-плана. Удаление плана уничтожает хостинг
зависящих от него сайтов; это не обычная пауза.
Private Endpoint тоже может продолжать тарифицироваться независимо от сайтов.

Для завершения эксперимента сначала сохрани нужные данные и список настроек.
Удаляй через Portal только заведомо созданные для этого стенда ресурсы в личной
подписке. Не удаляй `rg-shared` или другие общие группы только по совпадению имени:
убедись, что там нет чужих ресурсов. Entra-регистрации находятся вне resource groups
и требуют отдельной проверки/удаления, если больше не нужны.

## Официальная документация

- [Несколько приложений на одном App Service Plan и оплата](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans).
- [App Service VNet integration](https://learn.microsoft.com/en-us/azure/app-service/configure-vnet-integration-enable).
- [Ограничения доступа и Microsoft.Web service endpoint](https://learn.microsoft.com/en-us/azure/app-service/app-service-ip-restrictions).
- [Azure SQL Private Endpoint и обычное имя сервера](https://learn.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview?view=azuresql).
- [Бесплатное предложение Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/free-offer?view=azuresql).
- [Managed identity в Microsoft.Data.SqlClient и Azure extension](https://learn.microsoft.com/en-us/sql/connect/ado-net/sql/azure-active-directory-authentication?view=sql-server-ver17).
- [Managed identity в ODBC, UID для App Service](https://learn.microsoft.com/en-us/sql/connect/odbc/using-azure-active-directory?view=sql-server-ver17).
- [App Service Authentication с Entra](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-provider-aad).
- [Key Vault references и user-assigned identity](https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references).
- [Python runtime и установка зависимостей](https://learn.microsoft.com/en-us/azure/app-service/configure-language-python).
- [OIDC для GitHub Actions](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect).
