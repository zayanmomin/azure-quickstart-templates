@description('The location into which regional resources should be deployed.')
param location string = resourceGroup().location

@description('The name of the Front Door endpoint to create. This must be globally unique.')
param endpointName string = 'afd-${uniqueString(resourceGroup().id)}'

@description('The host name that should be used when connecting from Front Door to the origin.')
param originHostName string

@allowed([
  'Detection'
  'Prevention'
])
@description('The mode that the WAF should be deployed using. In \'Prevention\' mode, the WAF will block requests it detects as malicious. In \'Detection\' mode, the WAF will not block requests and will simply log the request.')
param wafMode string = 'Prevention'

@description('The list of managed rule sets to configure on the WAF.')
param wafManagedRuleSets array = [
  {
    ruleSetType: 'Microsoft_DefaultRuleSet'
    ruleSetVersion: '1.1'
  }
  {
    ruleSetType: 'Microsoft_BotManagerRuleSet'
    ruleSetVersion: '1.0'
  }
]

@description('The name of the Log Analytics workspace to create.')
param logAnalyticsWorkspaceName string = 'la-${uniqueString(resourceGroup().id)}'

var skuName = 'Premium_AzureFrontDoor' // The Microsoft-managed WAF rule sets require the premium SKU of Front Door.
var profileName = 'MyFrontDoor'
var originGroupName = 'MyOriginGroup'
var originName = 'MyOrigin'
var routeName = 'MyRoute'
var wafPolicyName = 'WafPolicy'
var securityPolicyName = 'SecurityPolicy'

resource profile 'Microsoft.Cdn/profiles@2020-09-01' = {
  name: profileName
  location: 'global'
  sku: {
    name: skuName
  }
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2020-09-01' = {
  name: endpointName
  parent: profile
  location: 'global'
  properties: {
    originResponseTimeoutSeconds: 240
    enabledState: 'Enabled'
  }
}

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2020-09-01' = {
  name: originGroupName
  parent: profile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 100
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2020-09-01' = {
  name: originName
  parent: originGroup
  properties: {
    hostName: originHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: originHostName
    priority: 1
    weight: 1000
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2020-09-01' = {
  name: routeName
  parent: endpoint
  dependsOn:[
    origin // This explicit dependency is required to ensure that the origin group is not empty when the route is created.
  ]
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    compressionSettings: {
      contentTypesToCompress: [
        'application/eot'
        'application/font'
        'application/font-sfnt'
        'application/javascript'
        'application/json'
        'application/opentype'
        'application/otf'
        'application/pkcs7-mime'
        'application/truetype'
        'application/ttf'
        'application/vnd.ms-fontobject'
        'application/xhtml+xml'
        'application/xml'
        'application/xml+rss'
        'application/x-font-opentype'
        'application/x-font-truetype'
        'application/x-font-ttf'
        'application/x-httpd-cgi'
        'application/x-javascript'
        'application/x-mpegurl'
        'application/x-opentype'
        'application/x-otf'
        'application/x-perl'
        'application/x-ttf'
        'font/eot'
        'font/ttf'
        'font/otf'
        'font/opentype'
        'image/svg+xml'
        'text/css'
        'text/csv'
        'text/html'
        'text/javascript'
        'text/js'
        'text/plain'
        'text/richtext'
        'text/tab-separated-values'
        'text/xml'
        'text/x-script'
        'text/x-component'
        'text/x-java-source'
      ]
      isCompressionEnabled: true
    }
    queryStringCachingBehavior: 'IgnoreQueryString'
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
}

resource wafPolicy 'Microsoft.Network/frontDoorWebApplicationFirewallPolicies@2020-11-01' = {
  name: wafPolicyName
  location: 'global'
  sku: {
    name: skuName
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
    }
    managedRules: {
      managedRuleSets: wafManagedRuleSets
    }
  }
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2020-09-01' = {
  parent: profile
  name: securityPolicyName
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-03-01-preview' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource logAnalyticsWorkspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2017-05-01-preview' = {
  scope: profile
  name: 'diagnosticSettings'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'FrontDoorWebApplicationFirewallLog'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: true
        }
      }
    ]
  }
}

output frontDoorEndpointHostName string = endpoint.properties.hostName