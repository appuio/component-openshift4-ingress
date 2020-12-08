# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added

- Initial implementation ([#1])
- Default wildcard cert ([#2])
- Node selector to target infra nodes ([#4])
- Secret with cloud credentials ([#5])

### Changed

- Do nothing if cloud does not support ACME ([#9])
- Remove usage of deprecated parameters ([#13])

### Fixed
- Allow `null` value for `ingressControllers` ([#3])
- Fix syntax error by quiting key `defaultCertificate` ([#10])
- Fix usage of cloud provider param ([#11])

[Unreleased]: https://github.com/appuio/component-openshift4-ingress/compare/44356edb4db73e762cd8896fb3b5a6f11f698799...HEAD

[#1]: https://github.com/appuio/component-openshift4-ingress/pull/1
[#2]: https://github.com/appuio/component-openshift4-ingress/pull/2
[#3]: https://github.com/appuio/component-openshift4-ingress/pull/3
[#4]: https://github.com/appuio/component-openshift4-ingress/pull/4
[#5]: https://github.com/appuio/component-openshift4-ingress/pull/5
[#9]: https://github.com/appuio/component-openshift4-ingress/pull/9
[#10]: https://github.com/appuio/component-openshift4-ingress/pull/10
[#11]: https://github.com/appuio/component-openshift4-ingress/pull/11
[#13]: https://github.com/appuio/component-openshift4-ingress/pull/13
