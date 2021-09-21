local certManager = import 'lib/cert-manager.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.openshift4_ingress;
local cloudcredentialv1 = 'cloudcredential.openshift.io/v1';
local credentialsSecretName = 'ingress-cert-issuer-credentials';
local hasCredentials = if std.objectHas(params.cloud, 'credentials') then true else false;

// credentialsrequest providerspecs for the supported clouds
local cloudCredentialsProviderSpec = {
  gcp: {
    apiVersion: cloudcredentialv1,
    kind: 'GCPProviderSpec',
    predefinedRoles: [ 'roles/dns.admin' ],
  },
  aws: {
    apiVersion: cloudcredentialv1,
    kind: 'AWSProviderSpec',
    statementEntries: [ {
      effect: 'Allow',
      action: [
        'route53:ChangeResourceRecordSets',
        'route53:ListResourceRecordSets',
      ],
      resource: 'arn:aws:route53:::hostedzone/*',
    }, {
      effect: 'Allow',
      action: [ 'route53:ListHostedZonesByName' ],
      resource: '*',
    } ],
  },
  azure: {
    apiVersion: cloudcredentialv1,
    kind: 'AzureProviderSpec',
    roleBindings: [ {
      role: 'DNS Zone Contributor',
    } ],
  },
};

local cloudCredentialsRequest =
  kube._Object(cloudcredentialv1, 'CredentialsRequest', 'ingress-cert-issuer') {
    metadata+: {
      namespace: 'openshift-cloud-credential-operator',
    },
    spec: {
      secretRef: {
        name: credentialsSecretName,
        namespace: params.namespace,
      },
      providerSpec:
        if std.objectHas(cloudCredentialsProviderSpec, params.cloud.provider) then
          cloudCredentialsProviderSpec[params.cloud.provider]
        else
          error 'Cloud provider "' + params.cloud.provider + '" is not implemented.',
    },
  };

// dns01 configuration for the supported cloud providers
local dns01solver = {
  gcp: {
    clouddns: {
      project: params.cloud.gcp.projectName,
      serviceAccountSecretRef: {
        name: credentialsSecretName,
        key: if hasCredentials then 'credentials' else 'service_account.json',
      },
    },
  },
  aws: {
    route53: {
      region: inv.parameters.facts.region,
      accessKeyID: params.cloud.aws.accessKey,
      secretAccessKeySecretRef: {
        name: credentialsSecretName,
        key: if hasCredentials then 'credentials' else 'aws_secret_access_key',
      },
    },
  },
  azure: {
    azuredns: {
      clientID: params.cloud.azure.clientID,
      clientSecretSecretRef: {
        name: credentialsSecretName,
        key: if hasCredentials then 'credentials' else 'azure_client_secret',
      },
      subscriptionID: params.cloud.azure.subscriptionID,
      tenantID: params.cloud.azure.tenantID,
      resourceGroupName: params.cloud.azure.resourceGroupName,
    },
  },
};

local issuerManifests = [
  if hasCredentials then
    // Setup secret with provided cloud credentials
    kube.Secret(credentialsSecretName) {
      stringData: {
        credentials: params.cloud.credentials,
      },
    }
  else
    // Request credentials from OpenShift Cloud Credential Operator
    cloudCredentialsRequest,
  // Setup custom issuer with DNS01 challenge using the provided or generated
  // credentials for the ingress cert.
  certManager.issuer('ingress-cert-issuer') {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      acme: {
        email: inv.parameters.cert_manager.letsencrypt_email,
        privateKeySecretRef: {
          name: 'ingress-cert-issuer',
        },
        server: 'https://acme-v02.api.letsencrypt.org/directory',
        solvers: [ {
          dns01:
            if std.objectHas(dns01solver, params.cloud.provider) then
              dns01solver[params.cloud.provider]
            else
              error 'Cloud provider "' + params.cloud.provider + '" is not implemented.',
        } ],
      },
    },
  },
];

{
  cert(certName, dnsNames): certManager.cert(certName) {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      secretName: certName,
      // configure cert to use the custom issuer
      issuerRef: {
        name: 'ingress-cert-issuer',
      },
      dnsNames: dnsNames,
    },
  },
  issuer: issuerManifests,
}
