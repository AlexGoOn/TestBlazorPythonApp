import json
import os
import unittest
from pathlib import Path


def resources(template):
    entries = template.get("resources", {})
    for resource in entries.values() if isinstance(entries, dict) else entries:
        yield resource
        properties = resource.get("properties")
        if isinstance(properties, dict) and isinstance(properties.get("template"), dict):
            yield from resources(properties["template"])


@unittest.skipUnless(os.environ.get("BICEP_COMPILED_TEMPLATE"), "Compile Bicep and set BICEP_COMPILED_TEMPLATE.")
class InfrastructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        template = json.loads(Path(os.environ["BICEP_COMPILED_TEMPLATE"]).read_text(encoding="utf-8-sig"))
        cls.entries = list(resources(template))
        cls.modules = {entry["name"]: entry for entry in cls.entries if isinstance(entry["name"], str)}

    def module_parameters(self, name):
        return {key: value["value"] for key, value in self.modules[name]["properties"]["parameters"].items()}

    def test_exactly_one_plan_two_apps_two_identities(self):
        for resource_type, count in (
            ("Microsoft.Web/serverfarms", 1),
            ("Microsoft.Web/sites", 2),
            ("Microsoft.ManagedIdentity/userAssignedIdentities", 2),
        ):
            self.assertEqual(
                len([entry for entry in self.entries
                     if entry["type"] == resource_type and not entry.get("existing")]),
                count,
            )
        plan = self.module_parameters("application-linux-plan")
        self.assertEqual(plan["skuCapacity"], 1)
        self.assertFalse(plan["zoneRedundant"])
        self.assertTrue(plan["reserved"])

    def test_shared_landing_zone_is_not_modified(self):
        for resource_type in (
            "Microsoft.Sql/servers", "Microsoft.Sql/servers/databases",
            "Microsoft.KeyVault/vaults", "Microsoft.Network/virtualNetworks",
            "Microsoft.Insights/components",
        ):
            self.assertFalse(any(entry["type"] == resource_type and not entry.get("existing")
                                 for entry in self.entries))

    def test_web_apps_have_distinct_azd_service_tags(self):
        for service in ("backend", "frontend"):
            parameters = self.module_parameters(f"application-{service}")
            self.assertIn(f"'azd-service-name', '{service}'", parameters["tags"])

    def test_python_allows_only_the_integration_subnet(self):
        backend = self.module_parameters("backend-webapp-avm")
        site = backend["siteConfig"]
        self.assertEqual(site["ipSecurityRestrictionsDefaultAction"], "Deny")
        self.assertEqual(len(site["ipSecurityRestrictions"]), 1)
        self.assertEqual(site["ipSecurityRestrictions"][0]["action"], "Allow")
        self.assertIn("vnetSubnetResourceId", site["ipSecurityRestrictions"][0])
        self.assertTrue(site["vnetRouteAllEnabled"])
        self.assertFalse(site["scmIpSecurityRestrictionsUseMain"])
        self.assertEqual(site["scmIpSecurityRestrictionsDefaultAction"], "Allow")
        self.assertEqual(site["appCommandLine"], "python azure_startup.py")

    def test_frontend_requires_easy_auth_and_key_vault(self):
        frontend = self.module_parameters("frontend-webapp-avm")
        configs = {config["name"]: config["properties"] for config in frontend["configs"]}
        auth = configs["authsettingsV2"]
        self.assertTrue(auth["platform"]["enabled"])
        self.assertTrue(auth["globalValidation"]["requireAuthentication"])
        self.assertEqual(auth["globalValidation"]["redirectToProvider"], "azureActiveDirectory")
        self.assertTrue(auth["httpSettings"]["requireHttps"])
        self.assertIn("keyVaultAccessIdentityResourceId", frontend)
        settings = configs["appsettings"]
        self.assertIn("@Microsoft.KeyVault", settings["MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"])
        self.assertIn("Active Directory Managed Identity", settings["ConnectionStrings__Sql"])
        self.assertEqual(settings["ASPNETCORE_ENVIRONMENT"], "Production")
        self.assertTrue(frontend["siteConfig"]["webSocketsEnabled"])

    def test_publishing_uses_https_and_not_basic_authentication(self):
        for name in ("frontend-webapp-avm", "backend-webapp-avm"):
            site = self.module_parameters(name)
            self.assertTrue(site["httpsOnly"])
            self.assertTrue(all(not policy["allow"] for policy in site["basicPublishingCredentialsPolicies"]))
            self.assertEqual(site["siteConfig"]["ftpsState"], "Disabled")
            self.assertEqual(site["siteConfig"]["minTlsVersion"], "1.2")
            configs = {config["name"]: config["properties"] for config in site["configs"]}
            self.assertIn("APPLICATIONINSIGHTS_CONNECTION_STRING", configs["appsettings"])
            self.assertIn("OTEL_SERVICE_NAME", configs["appsettings"])


if __name__ == "__main__":
    unittest.main()
