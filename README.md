# Sentinel Format (fmt) action

This is one of a suite of Sentinel related actions.

This action uses the `sentinel fmt` command to check that all Sentinel files in a directory are in the canonical format. This can be used to check that files are properly formatted before merging.

The output of the actions can be viewed from the Actions tab in the main repository view. If the actions are executed on a pull request event, a comment can be posted on the pull request.

## Inputs

* `check`

  By default, fmt checks if the input is properly formatted. If you set it to false, code will be formated in a canonical format.

  * Type: boolean
  * Optional
  * Default: true

  ```yaml
  with:
    check: false
  ```

* `version`

  The Sentinel version to install and execute. If set to `latest`, the latest stable version will be used.

  * type: string
  * Optional
  * Default: latest

  ```yaml
  with:
    version: latest
  ```

* `working_dir`

  The working directory to change into before executing Sentinel subcommands. Defaults to `.` which means use the root of the GitHub repository.

  * type: string
  * Optional
  * Default: '.'

  ```yaml
  with:
    working_dir: ./policies
  ```

* `comment`

  Whether or not to comment on GitHub pull request. Defaults to `true`.

  * type: boolean
  * Optional
  * Default: true

  ```yaml
  with:
    comment: false
  ```

* `delete_comment`
  
  Whether or not to delete previous comment on pull request. Defaults to `true`.

  * type: boolean
  * Optional
  * Default: true

  ```yaml
  with:
    delete_comment: false
  ```

## Outputs

* `exitcode`

  The exit code of the Sentinel fmt command.

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

The most common workflow is to run `sentinel fmt` on all of the Sentinel files in the root of the repository when a pull request is opened or updated. A comment will be posted to the pull request depending on the output. This workflow can be configured by adding the following content to the GitHub Actions workflow YAML file.

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
        uses: benyboy84/GitHubAction_sentinel-fmt@v1
        with:
          version: latest
          check: false
          working_dir: "./policies"
          comment: true
          delete_comment: true
```
