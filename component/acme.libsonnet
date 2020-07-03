local certManager = import 'lib/cert-manager.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.openshift4_ingress;
local cloudcredentialv1 = 'cloudcredential.openshift.io/v1';
local credentialsSecretName = 'ingress-cert-issuer-credentials';


{
  cert(certName, dnsNames): certManager.cert(certName) {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      secretName: certName,
      issuerRef: {
        name: 'ingress-cert-issuer',
      },
      dnsNames: dnsNames,
    },
  },
  issuer(): [
    kube._Object(cloudcredentialv1, 'CredentialsRequest', 'ingress-cert-issuer') {
      metadata+: {
        namespace: 'openshift-cloud-credential-operator',
      },
      spec: {
        secretRef: {
          name: credentialsSecretName,
          namespace: params.namespace,
        },
        providerSpec: if params.cloud.provider == 'gcp' then {
          apiVersion: cloudcredentialv1,
          kind: 'GCPProviderSpec',
          predefinedRoles: ['roles/dns.admin'],
        } else if params.cloud.provider == 'aws' then {
          apiVersion: cloudcredentialv1,
          kind: 'AWSProviderSpec',
          statementEntries: [{
            effect: 'Allow',
            action: [
              'route53:ChangeResourceRecordSets',
              'route53:ListResourceRecordSets',
            ],
            resource: 'arn:aws:route53:::hostedzone/*',
          }, {
            effect: 'Allow',
            action: ['route53:ListHostedZonesByName'],
            resource: '*',
          }],
        } else if params.cloud.provider == 'azure' then {
          apiVersion: cloudcredentialv1,
          kind: 'AzureProviderSpec',
          roleBindings: [{
            role: 'DNS Zone Contributor',
          }],
        } else
          error 'Cloud provider "' + params.cloud.provider + '" is not implemented.',
      },
    },
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
          solvers: [{
            dns01: if params.cloud.provider == 'gcp' then {
              clouddns: {
                project: params.cloud.gcp.projectName,
                serviceAccountSecretRef: {
                  name: credentialsSecretName,
                  key: 'service_account.json',
                },
              },
            } else if params.cloud.provider == 'aws' then {
              route53: {
                region: inv.parameters.cloud.region,
                accessKeyID: params.cloud.aws.accessKey,
                secretAccessKeySecretRef: {
                  name: credentialsSecretName,
                  key: 'aws_secret_access_key',
                },
              },
            } else if params.cloud.provider == 'azure' then {
              azuredns: {
                clientID: params.cloud.azure.clientID,
                clientSecretSecretRef: {
                  name: credentialsSecretName,
                  key: 'azure_client_secret',
                },
                subscriptionID: params.cloud.azure.subscriptionID,
                tenantID: params.cloud.azure.tenantID,
                resourceGroupName: params.cloud.azure.resourceGroupName,
              },
            } else error 'Cloud provider "' + params.cloud.provider + '" is not implemented.',
          }],
        },
      },
    },
  ],
}
