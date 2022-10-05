## Bump up document site version

- api.go.cd
- plugin-api.go.cd
- developer.go.cd
- docs.go.cd

To bump up above mentioned document site version run following command -

```bash
bundle install --path .bundle --binstubs
ORG=bdpiparva REPO_NAME=plugin-api.go.cd GITHUB_USER=foo GITHUB_TOKEN=bar NEXT_VERSION=18.12.0 VERSION_TO_RELEASE=18.11.0 bundle exec rake bump_docs_version
```

On build.gocd.org download `version.json` file from `installers` pipeline using fetch artifact task. Setup following environment variables at pipeline level

```yaml
ORG=bdpiparva 
GITHUB_USER=foo 
GITHUB_TOKEN=bar 
NEXT_VERSION=18.12.0 
```

Create a job with following task -

```bash
bundle install --path .bundle --binstubs
REPO_NAME=plugin-api.go.cd bundle exec rake bump_docs_version
```

Note: Here script is reading `VERSION_TO_RELEASE` from version.json file 
