# Release Signing Script (`sign_releases.py`)

This Python script automates the process of cryptographically signing GitHub release artifacts for a specified repository and re-uploading them along with their `.asc` signature files. This helps meet the OpenSSF "Signed-Releases" criteria by attesting to the provenance of the artifacts.

## Prerequisites

1.  **Python 3:** Ensure you have Python 3 installed on your system.
2.  **GnuPG (GPG):** GPG must be installed, and you need to have a GPG key pair generated and configured. The script will attempt to use the first available secret key suitable for signing.
3.  **Python Libraries:** Install the necessary Python libraries using pip:
    ```bash
    pip install requests python-gnupg
    ```
4.  **GitHub Personal Access Token:** You will need a GitHub Personal Access Token.
    *   **Permissions:** The token requires the `repo` scope (or `public_repo` if your repository is public and you only need to access/modify public releases).
    *   **Usage:** The script will prompt for this token if it's not provided via the `--github-token` command-line argument or the `GITHUB_TOKEN` environment variable.

## How to Run

1.  Navigate to the `scripts` directory within your project (e.g., `cd /path/to/your/project/scripts`).
2.  Execute the script from your terminal:

    ```bash
    python sign_releases.py OWNER/REPOSITORY_NAME
    ```
    Replace `OWNER/REPOSITORY_NAME` with the target repository (e.g., `nightconcept/almandine`).

### Command-Line Arguments

*   `repo` (Required): The repository name in `owner/repo` format (e.g., `nightconcept/almandine`).
*   `--github-token YOUR_GITHUB_TOKEN` (Optional): Your GitHub Personal Access Token. If not provided, the script will try to read it from the `GITHUB_TOKEN` environment variable or prompt you to enter it.
*   `--gpg-program /path/to/gpg` (Optional): Specify the full path to your GPG executable if it's not in your system's PATH (default is `gpg`).
*   `--num-releases N` (Optional): The number of recent releases to process. Defaults to `5`. The maximum is 30 (a GitHub API limit for some queries, and the OpenSSF check looks at the 30 most recent).
*   `--skip-already-signed` (Optional): If this flag is present, the script will skip processing an asset if a corresponding `.asc` signature file already exists in the release assets.
*   `--yes` (Optional): If this flag is present, the script will automatically confirm actions (like signing and uploading) without prompting the user. Use with caution.

### Script Behavior

When executed, the script will:
1.  Prompt for your GitHub Personal Access Token if not provided via argument or environment variable.
2.  Prompt for your GPG key passphrase (if your key is passphrase-protected).
3.  Identify the first available GPG secret key suitable for signing.
4.  Fetch the specified number of recent releases from the target GitHub repository.
5.  For each release:
    a.  Iterate through its assets.
    b.  Skip any files that appear to be existing signature files (e.g., `.asc`, `.sig`).
    c.  If `--skip-already-signed` is used, skip assets that already have a corresponding `.asc` signature uploaded.
    d.  Prompt for confirmation to sign and re-upload each eligible asset (unless `--yes` is used).
    e.  Download the asset to a temporary local directory.
    f.  Sign the downloaded asset using the identified GPG key, creating a detached signature file (`.asc`).
    g.  Upload the newly created `.asc` signature file to the GitHub release.
    h.  Clean up the temporary downloaded asset and signature file.
6.  Provide logging output for all actions and any errors encountered.

## Important Considerations

*   **GPG Key Selection:** The script automatically selects the first GPG secret key it finds that is suitable for signing. Ensure the desired key is available to GPG.
*   **Idempotency:** The `--skip-already-signed` flag helps prevent re-processing assets that have already been signed and had their signatures uploaded.
*   **Error Handling:** The script includes logging and attempts to handle common errors related to GitHub API interactions, GPG operations, and file system actions.
*   **Security:**
    *   Be cautious when entering your GitHub token and GPG passphrase.
    *   Avoid hardcoding sensitive credentials directly into scripts or committing them to version control. Using environment variables or interactive prompts (as the script does) is preferred.
*   **API Rate Limits:** While the script processes releases and assets one by one, be mindful of GitHub API rate limits if you are processing a very large number of releases or assets frequently.
*   **Manual Testing:** It is highly recommended to first test this script on a fork or a test repository with a few sample releases to ensure it behaves as expected with your GPG setup and GitHub token before running it on your main project repository.