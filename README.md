# Sentinel GitHub Actions

Sentinel GitHub Actions allow you to execute Sentinel commands within GitHub Actions.

The output of the actions can be viewed from the Actions tab in the main repository view. If the actions are executed on a pull request event, a comment may be posted on the pull request.

Sentinel GitHub Actions are a single GitHub Action that executes different Sentinel subcommands depending on the content of the GitHub Actions YAML file.

# Success Criteria

An exit code of `0` is considered a successful execution.

## Inputs

* `command`

  The Sentinel command to execute. Valid values are `fmt` and `test`.

  - type: string
  - Required

  ```yaml
  with:
    command: test
  ```

* `version`

  The Sentinel version to install and execute. If set to `latest`, the latest stable version will be used.

  - type: string
  - Optional
  - Default: latest

  ```yaml
  with:
    version: latest
  ```

* `comment`

  Whether or not to comment on GitHub pull requests. Defaults to `true`.

  - type: boolean
  - Optional
  - Default: true

  ```yaml
  with:
    comment: false
  ```

* `working_dir`

  The working directory to change into before executing Sentinel subcommands. Defaults to `.` which means use the root of the GitHub repository.

  - type: string
  - Optional
  - Default: '.'

  ```yaml
  with:
    working_dir: ./policies
  ```

## Outputs

* `output`

  The Sentinel outputs.

## Environment Variables

* `GITHUB_TOKEN`

  The GitHub authorization token to use to add a comment to a PR. 
  The token provided by GitHub Actions can be used - it can be passed by
  using the `${{ secrets.GITHUB_TOKEN }}` expression, e.g.

  ```yaml
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  ```

  The token provided by GitHub Actions will work with the default permissions.
  The minimum permissions are `pull-requests: write`.
  It will also likely need `contents: read` so the job can checkout the repo.

## Example usage

The most common workflow is to run `sentinel fmt`, `sentinel test` on all of the Sentinel files in the root of the repository when a pull request is opened or updated. A comment will be posted to the pull request depending on the output of the Sentinel subcommand being executed. This workflow can be configured by adding the following content to the GitHub Actions workflow YAML file.

```yaml
name: 'Sentinel GitHub Actions'
on:
  - pull_request
jobs:
  sentinel:
    name: 'Sentinel'
    runs-on: ubuntu-latest
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - name: 'Checkout'
        uses: actions/checkout@master
      - name: 'Sentinel Format'
        uses: benyboy84/GitHubAction_Sentinel@v1
        with:
          version: latest
          command: 'fmt'
          working_dir: '.'
          comment: true
      - name: 'Sentinel Test'
        uses: benyboy84/GitHubAction_Sentinel@v1
        with:
          version: latest
          command: 'test'
          working_dir: '.'
          comment: true
```