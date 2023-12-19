#!/bin/bash

echo "INFO     | Executing Sentinel commands to format code or test policies."

# check if variable is array, returns 0 on success, 1 otherwise
# @param: mixed 
IS_ARRAY()
{   # Detect if arg is an array, returns 0 on sucess, 1 otherwise
    [ -z "$1" ] && return 1
    if [ -n "$BASH" ]; then
        declare -p ${1} 2> /dev/null | grep 'declare \-a' >/dev/null && return 0
    fi
    return 1
}

function stripColors {
  echo "${1}" | sed 's/\x1b\[[0-9;]*m//g'
}

# Required inputs

# Validate input command.
if [[ ! "$INPUT_COMMAND" =~ ^(fmt|test)$ ]]; then
    echo "ERROR    | Unsupported command \"$INPUT_COMMAND\" for input \"command\". Valid values are \"fmt\" or \"test\"."
    exit 1
fi

# Optional inputs

# Validate input version.
if [[ -n "$INPUT_VERSION" ]]; then
  version=$INPUT_VERSION
else
  version="latest"
fi

# Validate input comment.
if [[ ! "$INPUT_COMMENT" =~ ^(true|false)$ ]]; then
    echo "ERROR    | Unsupported command \"$INPUT_COMMENT\" for input \"comment\". Valid values are \"true\" or \"false\"."
    exit 1
fi

# Validate input working_dir.
WorkingDir="."
if [[ -n "$INPUT_WORKING_DIR" ]]; then
    if [[ -d "$INPUT_WORKING_DIR" || -f "$INPUT_WORKING_DIR" ]]; then
        WorkingDir=$INPUT_WORKING_DIR
        cd $WorkingDir
    else
        exit_code=1
        echo "ERROR    | Working directory does not exist: \"$INPUT_WORKING_DIR\"."
        exit 1
    fi
fi

if [[ "${ersion}" == "latest" ]]; then
  echo "INFO     | Checking the latest version of Sentinel"
  version=$(curl -sL https://releases.hashicorp.com/sentinel/index.json | jq -r '.versions[].version' | grep -v '[-].*' | sort -rV | head -n 1)

  if [[ -z "${version}" ]]; then
    echo "ERROR    | Failed to fetch the latest version"
    exit 1
  fi
fi

url="https://releases.hashicorp.com/sentinel/${version}/sentinel_${version}_linux_amd64.zip"

echo "INFO     | Downloading Sentinel ${version}"
curl -s -S -L -o /tmp/sentinel_${version} ${url}
if [ "${?}" -ne 0 ]; then
  echo "ERROR    | Failed to download Sentinel ${version}"
  exit 1
fi
echo "INFO     | Successfully downloaded Sentinel ${version}"

echo "INFO     | Unzipping Sentinel ${version}"
unzip -d /usr/local/bin /tmp/sentinel_${version}
# unzip -d /usr/local/bin /tmp/sentinel_${version} &> /dev/null
if [ "${?}" -ne 0 ]; then
  echo "ERROR    | Failed to unzip Sentinel ${version}"
  exit 1
fi
echo "INFO     | Successfully unzipped Sentinel ${version}"

if [[ "$INPUT_COMMAND" == 'fmt' ]]; then
  # Gather the output of `sentinel fmt`.
  echo "INFO     | Checking if Sentinel files in ${WorkingDir} are correctly formatted"
  fmtOutput=$(sentinel fmt -check=true -write=false 2>&1)
  exit_code=${?}

  # Output informations for future use.
  echo "output=$fmtOutput" >> $GITHUB_OUTPUT

  # Exit code of 0 indicates success. Print the output and exit.
  if [ ${exit_code} -eq 0 ]; then
    echo "INFO     | Sentinel files in ${WorkingDir} are correctly formatted"
    echo "${fmtOutput}"
  fi

  # Exit code of 2 indicates a parse error. Print the output and exit.
  if [ ${exit_code} -eq 2 ]; then
    echo "ERROR    | Failed to parse Sentinel files"
    echo "${fmtOutput}"
    pr_comment="### GitHub Action Sentinel
<details><summary>Show Output</summary>
<p>
$fmtOutput
</p>
</details>"
  pr_comment_wrapper=$(stripColors "${pr_comment}")
  fi

  # Exit code of !0 and !2 indicates failure.
  echo "ERROR    | Sentinel files in ${WorkingDir} are incorrectly formatted"
  echo "${fmtOutput}"
  echo "ERROR    | The following files in ${WorkingDir} are incorrectly formatted"
  fmtFileList=$(sentinel fmt -check=true -write=false ${WorkingDir})
  echo "${fmtFileList}"

  pr_comment="### GitHub Action Sentinel"
  for file in ${fmtFileList}; do
    fmtFileDiff=$(sentinel fmt -write=false "${file}" | sed -n '/@@.*/,//{/@@.*/d;p}')
    pr_comment="${pr_comment}
<details><summary><code>${WorkingDir}/${file}</code></summary>
\`\`\`diff
${fmtFileDiff}
\`\`\`
</details>"
    done
    pr_comment_wrapper=$(stripColors "${pr_comment}")

else

  # Gather the output of `sentinel test`.
  echo "INFO     | Validating Sentinel policies in ${WorkingDir}"
  testOutput=$(sentinel test 2>&1)
  exit_code=${?}

  # Output informations for future use.
  echo "output=$testOutput" >> $GITHUB_OUTPUT

  # Exit code of 0 indicates success. Print the output and exit.
  if [ ${exit_code} -eq 0 ]; then
    echo "INFO     | Successfully test Sentinel policies in ${WorkingDir}"
    echo "${testOutput}"
  fi

  # Exit code of !0 indicates failure.
  echo "ERROR    | Failed to test Sentinel policies in ${WorkingDir}"
  echo "${testOutput}"
  pr_comment="### GitHub Action Sentinel
<details><summary>Show Output</summary>
<p>
$testOutput
</p>
</details>"
  pr_comment_wrapper=$(stripColors "${pr_comment}")
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
            pr_comment_uri=$(jq -r ".repository.issue_comment_url" "$GITHUB_EVENT_PATH" | sed "s|{/number}||g")
            pr_comment_id=$(curl -sS -H "$auth_header" -H "$accept_header" -L "$pr_comments_url" | jq '.[] | select(.body|test ("### GitHub Action Sentinel")) | .id')
            if [ "$pr_comment_id" ]; then
                if [[ $(IS_ARRAY $pr_comment_id)  -ne 0 ]]; then
                    echo "INFO     | Found existing pull request comment: $pr_comment_id. Deleting."
                    pr_comment_url="$pr_comment_uri/$pr_comment_id"
                    {
                        curl -sS -X DELETE -H "$auth_header" -H "$accept_header" -L "$pr_comment_url" > /dev/null
                    } ||
                    {
                        echo "ERROR    | Unable to delete existing comment in pull request."
                    }
                else
                    echo "WARNING  | Pull request contain many comments with \"### GitHub Action Sentinel\" in the body."
                    echo "WARNING  | Existing pull request comments won't be delete."
                fi
            else
                echo "INFO     | No existing pull request comment found."
            fi
            if [[ $exit_code -ne 0 ]]; then
                # Add comment to pull request.
                body="$pr_comment_wrapper"
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