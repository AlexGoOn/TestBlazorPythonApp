# Rules

## Be brief

Have comments and documents to be a source of truth, not repetition of what already written in code or file structure. Users of this repo can read code.

## Use AVM

Use Azure verified modules for bicep infra.

## Give different names to bicep modules

If you have in main.bicep

```
module githubApi './app/apim-github.bicep' = {
  name: 'github-api'
  ...
}
```

And in ./app/apim-github.bicep

```
module githubApi 'br/public:avm/res/api-management/service/api:0.1.1' = {
  name: 'github-api'
  ...
}
```

Bicep will compile, but deployment will be stuck with error because two deployments with same name 'github-api' will be created.

Name these modules differently.
