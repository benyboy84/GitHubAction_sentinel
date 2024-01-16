#!/bin/bash

echo "INFO     | Executing Sentinel command to format code policies."

# Validate input `check`.
if [[ ! "${INPUT_CHECK}" =~ ^(true|false)$ ]]; then
  echo "ERROR    | Unsupported command \"${INPUT_CHECK}\" for input \"check\". Valid values are \"true\" or \"false\"."
  exit 1
fi

# Validate input `version`.
if [[ -n "${INPUT_VERSION}" ]]; then
  version=${INPUT_VERSION}
else
  version="latest"
fi

# Find latest version.`
if [[ "${version}" == "latest" ]]; then
  echo "INFO     | Checking the latest version of Sentinel."
  version=$(curl -sL https://releases.hashicorp.com/sentinel/index.json | jq -r '.versions[].version' | grep -v '[-].*' | sort -rV | head -n 1)
  if [[ -z "${version}" ]]; then
    echo "ERROR    | Failed to fetch the latest version."
    exit 1
  fi
fi

# Validate input `working_dir`.
working_dir="."
if [[ -n "${INPUT_WORKING_DIR}" ]]; then
  if [[ -d "${INPUT_WORKING_DIR}" || -f "${INPUT_WORKING_DIR}" ]]; then
    working_dir=${INPUT_WORKING_DIR}
    cd "${working_dir}" || exit 1
  else
    echo "ERROR    | Working directory does not exist: \"${INPUT_WORKING_DIR}\"."
    exit 1
  fi
fi

# Validate `subdirectories`.
if [[ ! "${INPUT_SUBDIRECTORIES}" =~ ^(true|false)$ ]]; then
  echo "ERROR    | Unsupported command \"${INPUT_SUBDIRECTORIES}\" for input \"subdirectories\". Valid values are \"true\" or \"false\"."
  exit 1
fi

# Validate `input comment`.
if [[ ! "${INPUT_COMMENT}" =~ ^(true|false)$ ]]; then
  echo "ERROR    | Unsupported command \"${INPUT_COMMENT}\" for input \"comment\". Valid values are \"true\" or \"false\"."
  exit 1
fi

# Validate `input delete_comment`.
if [[ ! "${INPUT_DELETE_COMMENT}" =~ ^(true|false)$ ]]; then
  echo "ERROR    | Unsupported command \"${INPUT_DELETE_COMMENT}\" for input \"delete_comment\". Valid values are \"true\" or \"false\"."
  exit 1
fi

echo "INFO     | Downloading Sentinel v${version}."
url="https://releases.hashicorp.com/sentinel/${version}/sentinel_${version}_linux_amd64.zip"
if ! curl -s -S -L -o "/tmp/sentinel_${version}" "${url}"; then
  echo "ERROR    | Failed to download Sentinel v${version}."
  exit 1
fi
echo "INFO     | Successfully downloaded Sentinel v${version}."

echo "INFO     | Unzipping Sentinel v${version}."
if ! unzip -o -d /usr/local/bin "/tmp/sentinel_${version}" &> /dev/null; then
  echo "ERROR    | Failed to unzip Sentinel v${version}."
  exit 1
fi
echo "INFO     | Successfully unzipped Sentinel v${version}."

# Gather the output of `sentinel fmt -check=true -write=false`.
fmt_parse_error=()
fmt_check_error=()
fmt_check_success=()
if [[ ${INPUT_SUBDIRECTORIES} == true ]]; then
  policies=$(find . -name "*.sentinel" -type f -not -path '*/test/*/*')
else
  policies=$(find . -maxdepth 1 -name "*.sentinel")
fi
for file in ${policies}; do
  echo "INFO     | Checking if Sentinel files ${file} is properly formatted."
  sentinel fmt -check=true -write=false "${file}" >/dev/null
  exit_code=${?}
  case ${exit_code} in 
    0)
      # Exit code of 0 indicates success.
      echo "INFO     | Sentinel file in ${file} is properly formatted."
      fmt_check_success+=("${file}")
      ;; 
    1)
      # Exit code of 1 indicates a parse error.
      echo "ERROR    | Failed to parse Sentinel file ${file}."
      fmt_parse_error+=("${file}")
      ;; 
    2)
      if [[ ${INPUT_CHECK} == false ]]; then
        echo "WARNING  | Sentinel file ${file} is improperly formatted."
      else
        echo "ERROR    | Sentinel file ${file} is improperly formatted."
      fi
      fmt_check_error+=("${file}")
      ;;
  esac
done

# Gather the output of `sentinel fmt -check=false -write=true`.
fmt_format_error=()
fmt_format_success=()
if [[ ${INPUT_CHECK} == false && ${#fmt_check_error[@]} -ne 0 ]]; then
  echo "INFO     | Sentinel file(s) are being formatted."
  for file in "${fmt_check_error[@]}"; do
    echo "INFO     | Formatting Sentinel file ${file}"
    sentinel fmt -check=false -write=true "${file}" >/dev/null
    fmt_exit_code=${?}
    if [[ ${fmt_exit_code} -ne 0 ]]; then
      echo "ERROR    | Failed to format file ${file}."
      fmt_format_error+=("${file}")
    else
      echo "INFO     | Sentinel file v${file} has been formatted."
      fmt_format_success+=("${file}")
    fi
  done
fi

# Adding comment to pull request.
if [[ ${INPUT_COMMENT} == true ]]; then

  # Creating pull request comment.
  if [[ ${#fmt_parse_error[@]} -ne 0 || (${INPUT_CHECK} == false && ${#fmt_format_error[@]} -ne 0) || (${INPUT_CHECK} == true && ${#fmt_check_error[@]} -ne 0) ]]; then
    pr_comment="### Sentinel Format - Failed"
  else
    pr_comment="### Sentinel Format - Successful"
  fi
  
  if [[ ${#fmt_parse_error[@]} -ne 0 ]]; then
    pr_comment="${pr_comment}
Failed to parse the following files:
<details><summary><code>Show Output</code></summary>
<p>

\`\`\`diff"
    for file in "${fmt_parse_error[@]}"; do
      pr_comment="${pr_comment}
${file}"
    done
    pr_comment="${pr_comment}
\`\`\`
</p>
</details>"
  fi
  if [[ ${INPUT_CHECK} == false && ${#fmt_check_error[@]} -ne 0 ]]; then
    if [[ ${#fmt_format_error[@]} -ne 0 ]]; then
      pr_comment="${pr_comment}
Failed to format the following files:
<details><summary><code>Show Output</code></summary>
<p>

\`\`\`diff"
      for file in "${fmt_format_error[@]}"; do
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
      for file in "${fmt_format_success[@]}"; do
        pr_comment="${pr_comment}
${file}"
      done
      pr_comment="${pr_comment}
\`\`\`
</p>
</details>"
    fi
  else
    if [[ ${#fmt_check_error[@]} -ne 0 ]]; then
      pr_comment="${pr_comment}
The following files are improperly formatted:
<details><summary><code>Show Output</code></summary>
<p>

\`\`\`diff"
      for file in "${fmt_check_error[@]}"; do
        pr_comment="${pr_comment}
${file}"
      done
      pr_comment="${pr_comment}
\`\`\`
</p>
</details>"
    fi
  fi
  if [[ ${#fmt_check_success[@]} -ne 0 ]]; then
    pr_comment="${pr_comment}
The following files are properly formatted:
<details><summary><code>Show Output</code></summary>
<p>

\`\`\`diff"
    for file in "${fmt_check_success[@]}"; do
      pr_comment="${pr_comment}
${file}"
    done
    pr_comment="${pr_comment}
\`\`\`
</p>
</details>"
  fi

  #if [[ "${GITHUB_EVENT_NAME}" != "push" && "${GITHUB_EVENT_NAME}" != "pull_request" && "${GITHUB_EVENT_NAME}" != "issue_comment" && "${GITHUB_EVENT_NAME}" != "pull_request_review_comment" && "${GITHUB_EVENT_NAME}" != "pull_request_target" && "${GITHUB_EVENT_NAME}" != "pull_request_review" ]]; then
  if [[ "${GITHUB_EVENT_NAME}" != "pull_request" && "${GITHUB_EVENT_NAME}" != "issue_comment" ]]; then
    echo "WARNING  | ${GITHUB_EVENT_NAME} event does not relate to a pull request."
  else
    if [[ -z ${GITHUB_TOKEN} ]]; then
      echo "WARNING  | GITHUB_TOKEN not defined. Pull request comment is not possible without a GitHub token."
    else
      accept_header="Accept: application/vnd.github.v3+json"
      auth_header="Authorization: token ${GITHUB_TOKEN}"
      content_header="Content-Type: application/json"
      if [[ "${GITHUB_EVENT_NAME}" == "issue_comment" ]]; then
        pr_comments_url=$(jq -r ".issue.comments_url" "${GITHUB_EVENT_PATH}")
      else
        pr_comments_url=$(jq -r ".pull_request.comments_url" "${GITHUB_EVENT_PATH}")
      fi
      if [[ "${INPUT_DELETE_COMMENT}" == true ]]; then
        pr_comment_uri=$(jq -r ".repository.issue_comment_url" "${GITHUB_EVENT_PATH}" | sed "s|{/number}||g")
        pr_comment_id=$(curl -sS -H "${auth_header}" -H "${accept_header}" -L "${pr_comments_url}" | jq '.[] | select(.body|test ("### Sentinel Format")) | .id')
        if [ "${pr_comment_id}" ]; then
          if (( $(grep -c . <<<"${pr_comment_id}") > 1 )); then
            echo "WARNING  | Pull request contain many comments with \"### Sentinel Format\" in the body."
            echo "WARNING  | Existing pull request comments won't be delete."
          else
            echo "INFO     | Found existing pull request comment: ${pr_comment_id}. Deleting..."
            pr_comment_url="${pr_comment_uri}/${pr_comment_id}"
            {
              curl -sS -X DELETE -H "${auth_header}" -H "${accept_header}" -L "${pr_comment_url}" > /dev/null
            } ||
            {
              echo "ERROR    | Unable to delete existing comment in pull request."
            }
          fi
        else
          echo "INFO     | No existing pull request comment found."
        fi
      fi
      if [[ ${exit_code} -ne 0 ]]; then
        # Add comment to pull request.
        body="${pr_comment}"
        pr_payload=$(echo '{}' | jq --arg body "${body}" '.body = $body')
        echo "INFO     | Adding comment to pull request."
        {
            curl -sS -X POST -H "${auth_header}" -H "${accept_header}" -H "${content_header}" -d "${pr_payload}" -L "${pr_comments_url}" > /dev/null
        } ||
        {
            echo "ERROR    | Unable to add comment to pull request."
        }
      fi
    fi
  fi
fi

# Exit with the result based on the `check`property
if [[ ${#fmt_parse_error[@]} -ne 0 ]]; then
  # 'fmt_parse_error' not empty indicates a parse error.
  exit_code=1
elif [[ ${#fmt_check_error[@]} -ne 0 ]]; then
  # 'fmt_check_error' not empty indicates that file is improperly formatted.
  if [[ ${INPUT_CHECK} == true ]]; then
    if [[ ${#fmt_format_error[@]} -ne 0 ]]; then
      # 'fmt_format_error' not empty indicates a formatting error.
      exit_code=1
    else
      # 'fmt_format_error' empty indicates have been formatted properly.
      exit_code=2
    fi
  else
    exit_code=2
  fi
else
  # 'fmt_parse_error' and 'fmt_check_error' empty indicates that success.
  exit_code=0
fi

echo "exitcode=${exit_code}" >> "${GITHUB_OUTPUT}"

# Exit with the result based on the `check`property
if [[ ${INPUT_CHECK} == true ]]; then
    exit $exit_code
else
  if [[ ${exit_code} -eq 2 ]]; then
    exit 0
  else 
    exit $exit_code
  fi
fi