#!/bin/bash

echo "INFO     | Executing Sentinel commands to format code or test policies."

# check if variable is array, returns 0 on success, 1 otherwise
# @param: mixed 
IS_ARRAY()
{   # Detect if arg is an array, returns 0 on sucess, 1 otherwise
    [ -z "$1" ] && return 1
    if [ -n "${BASH}" ]; then
        declare -p ${1} 2> /dev/null | grep 'declare \-a' >/dev/null && return 0
    fi
    return 1
}

# Optional inputs

# Validate input check.
if [[ ! "${INPUT_CHECK}" =~ ^(true|false)$ ]]; then
    echo "ERROR    | Unsupported command \"${INPUT_CHECK}\" for input \"check\". Valid values are \"true\" or \"false\"."
    exit 1
fi

# Validate input version.
if [[ -n "${INPUT_VERSION}" ]]; then
  version=${INPUT_VERSION}
else
  version="latest"
fi

# Validate input comment.
if [[ ! "${INPUT_COMMENT}" =~ ^(true|false)$ ]]; then
    echo "ERROR    | Unsupported command \"${INPUT_COMMENT}\" for input \"comment\". Valid values are \"true\" or \"false\"."
    exit 1
fi

# Validate input working_dir.
working_dir="."
if [[ -n "${INPUT_WORKING_DIR}" ]]; then
    if [[ -d "${INPUT_WORKING_DIR}" || -f "${INPUT_WORKING_DIR}" ]]; then
        working_dir=${INPUT_WORKING_DIR}
        cd ${working_dir}
    else
        echo "ERROR    | Working directory does not exist: \"${INPUT_WORKING_DIR}\"."
        exit 1
    fi
fi

if [[ "${version}" == "latest" ]]; then
  echo "INFO     | Checking the latest version of Sentinel."
  version=$(curl -sL https://releases.hashicorp.com/sentinel/index.json | jq -r '.versions[].version' | grep -v '[-].*' | sort -rV | head -n 1)

  if [[ -z "${version}" ]]; then
    echo "ERROR    | Failed to fetch the latest version."
    exit 1
  fi
fi

url="https://releases.hashicorp.com/sentinel/${version}/sentinel_${version}_linux_amd64.zip"

echo "INFO     | Downloading Sentinel v${version}."
curl -s -S -L -o /tmp/sentinel_${version} ${url}
if [ "${?}" -ne 0 ]; then
  echo "ERROR    | Failed to download Sentinel v${version}."
  exit 1
fi
echo "INFO     | Successfully downloaded Sentinel v${version}."

echo "INFO     | Unzipping Sentinel v${version}."
unzip -d /usr/local/bin /tmp/sentinel_${version} &> /dev/null
if [ "${?}" -ne 0 ]; then
  echo "ERROR    | Failed to unzip Sentinel v${version}."
  exit 1
fi
echo "INFO     | Successfully unzipped Sentinel v${version}."

# Gather the output of `sentinel fmt`.
fmt_parse_error=()
fmt_check_error=()
policies=$(find . -maxdepth 1 -name "*.sentinel")
for file in ${policies}; do
  basename="$(basename ${file})"
  echo "INFO     | Checking if Sentinel files ${basename} is correctly formatted."
  fmt_output=$(sentinel fmt -check=true -write=false ${basename} 2>&1)
  exit_code=${?}
  # Exit code of 0 indicates success.
  if [ ${exit_code} -eq 0 ]; then
    echo "INFO     | Sentinel file in ${basename} is correctly formatted."
  fi
  # Exit code of 1 indicates a parse error.
  if [ ${exit_code} -eq 1 ]; then
    echo "ERROR    | Failed to parse Sentinel file ${basename}."
    fmt_parse_error+=("${basename}")
  fi
  # Exit code of 2 indicates that file is incorrectly formatted.
  if [ ${exit_code} -eq 2 ]; then
    echo "ERROR    | Sentinel file ${basename} is incorrectly formatted."
    fmt_check_error+=("${basename}")
  fi
done

if [[ ${#fmt_parse_error[@]} -ne 0 ]]; then
  # 'fmt_parse_error' not empty indicates  a parse error.
  exit_code=1
elif [[ ${#fmt_check_error[@]} -ne 0 ]]; then
  # 'fmt_check_error' not empty indicates that file is incorrectly formatted.
  exit_code=2
else
  # 'fmt_parse_error' and 'fmt_check_error' empty indicates that success.
  exit_code=0
fi

fmt_format_error=()
fmt_format_success=()
if [[ ${INPUT_CHECK} == false ]]; then
  echo "INFO     | Sentinel file(s) are being formatted."
  for file in ${fmt_check_error}; do
    echo "INFO     | Formatting Sentinel file ${file}"
    fmt_output=$(sentinel fmt -check=false -write=true ${file} 2>&1)
    fmt_exit_code=${?}
    if [[ ${fmt_exit_code} -ne 0 ]]; then
      echo "ERROR    | Failed to format file ${file}."
      fmt_format_error+=(${file})
    else
      echo "INFO     | Sentinel file v${file} has been formatted."
      fmt_format_success+=(${file})
    fi
  done
  pr_comment="### GitHub Action Sentinel"
  if [[ ${#fmt_format_error[@]} -ne 0 ]]; then
    pr_comment="${pr_comment}
Failed to format Sentinel files:
<details><summary><code>Show Output</code></summary>
<p>

\`\`\`diff"
    for file in ${fmt_format_error}; do
      pr_comment="${pr_comment}
${file}"
    done
    pr_comment="${pr_comment}
\`\`\`
</p>
</details>"
  fi
  if [[ ${#fmt_format_success[@]} -ne 0 ]]; then
    pr_comment="${pr_comment}
The following files have been formatted:
<details><summary><code>Show Output</code></summary>
<p>

\`\`\`diff"
    for file in ${fmt_format_success}; do
      pr_comment="${pr_comment}
${file}"
    done
    pr_comment="${pr_comment}
\`\`\`
</p>
</details><br>
Make sure to perform a 'git pull' to update your local repository."
  fi
else
  pr_comment="### GitHub Action Sentinel"
  if [[ ${#fmt_parse_error[@]} -ne 0 ]]; then
    pr_comment="${pr_comment}
Failed to parse Sentinel files:
<details><summary><code>Show Output</code></summary>
<p>

\`\`\`diff"
    for file in ${fmt_parse_error}; do
      pr_comment="${pr_comment}
${file}"
    done
    pr_comment="${pr_comment}
\`\`\`
</p>
</details>"
  fi
  if [[ ${#fmt_check_error[@]} -ne 0 ]]; then
    pr_comment="${pr_comment}
Sentinel files are incorrectly formatted:
<details><summary><code>Show Output</code></summary>
<p>

\`\`\`diff"
    for file in ${fmt_check_error}; do
      pr_comment="${pr_comment}
${file}"
    done
    pr_comment="${pr_comment}
\`\`\`
</p>
</details>"
  fi
fi

if [[ $INPUT_COMMENT == true ]]; then
    #if [[ "$GITHUB_EVENT_NAME" != "push" && "$GITHUB_EVENT_NAME" != "pull_request" && "$GITHUB_EVENT_NAME" != "issue_comment" && "$GITHUB_EVENT_NAME" != "pull_request_review_comment" && "$GITHUB_EVENT_NAME" != "pull_request_target" && "$GITHUB_EVENT_NAME" != "pull_request_review" ]]; then
    if [[ "$GITHUB_EVENT_NAME" != "pull_request" && "$GITHUB_EVENT_NAME" != "issue_comment" ]]; then
        echo "WARNING  | $GITHUB_EVENT_NAME event does not relate to a pull request."
    else
        if [[ -z GITHUB_TOKEN ]]; then
            echo "WARNING  | GITHUB_TOKEN not defined. Pull request comment is not possible without a GitHub token."
        else
            # Look for an existing pull request comment and delete
            echo "INFO     | Looking for an existing pull request comment."
            accept_header="Accept: application/vnd.github.v3+json"
            auth_header="Authorization: token $GITHUB_TOKEN"
            content_header="Content-Type: application/json"
            if [[ "$GITHUB_EVENT_NAME" == "issue_comment" ]]; then
                pr_comments_url=$(jq -r ".issue.comments_url" "$GITHUB_EVENT_PATH")
            else
                pr_comments_url=$(jq -r ".pull_request.comments_url" "$GITHUB_EVENT_PATH")
            fi
            # pr_comment_uri=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")
            # pr_comment_id=$(curl -sS -H "$auth_header" -H "$accept_header" -L "$pr_comments_url" | jq '.[] | select(.body|test ("### GitHub Action Sentinel")) | .id')
            # if [ "$pr_comment_id" ]; then
            #     if [[ $(IS_ARRAY $pr_comment_id)  -ne 0 ]]; then
            #         echo "INFO     | Found existing pull request comment: $pr_comment_id. Deleting."
            #         pr_comment_url="$pr_comment_uri/$pr_comment_id"
            #         {
            #             curl -sS -X DELETE -H "$auth_header" -H "$accept_header" -L "$pr_comment_url" > /dev/null
            #         } ||
            #         {
            #             echo "ERROR    | Unable to delete existing comment in pull request."
            #         }
            #     else
            #         echo "WARNING  | Pull request contain many comments with \"### GitHub Action Sentinel\" in the body."
            #         echo "WARNING  | Existing pull request comments won't be delete."
            #     fi
            # else
            #     echo "INFO     | No existing pull request comment found."
            # fi
            if [[ $exit_code -ne 0 ]]; then
                # Add comment to pull request.
                body="$pr_comment"
                pr_payload=$(echo '{}' | jq --arg body "$body" '.body = $body')
                echo "INFO     | Adding comment to pull request."
                {
                    curl -sS -X POST -H "$auth_header" -H "$accept_header" -H "$content_header" -d "$pr_payload" -L "$pr_comments_url" > /dev/null
                } ||
                {
                    echo "ERROR    | Unable to add comment to pull request."
                }
            fi
        fi
    fi
fi

exit $exit_code 