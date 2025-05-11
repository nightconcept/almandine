import os
import requests
import gnupg
import getpass
import json
import argparse
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Constants
GITHUB_API_URL = "https://api.github.com"
RELEASES_PER_PAGE = 30 # Max allowed by GitHub API for releases, check looks for 30 most recent
SIGNATURE_EXTENSIONS = [".minisig", ".asc", ".sig", ".sign", ".sigstore", ".intoto.jsonl"]

def get_github_releases(repo_owner, repo_name, token, num_releases_to_check):
    """Fetches the specified number of releases from GitHub."""
    releases = []
    page = 1
    while len(releases) < num_releases_to_check:
        url = f"{GITHUB_API_URL}/repos/{repo_owner}/{repo_name}/releases?per_page={RELEASES_PER_PAGE}&page={page}"
        headers = {"Authorization": f"token {token}"}
        try:
            response = requests.get(url, headers=headers)
            response.raise_for_status()
            current_page_releases = response.json()
            if not current_page_releases:
                break # No more releases
            releases.extend(current_page_releases)
            if len(current_page_releases) < RELEASES_PER_PAGE:
                break # Last page
            page += 1
        except requests.exceptions.RequestException as e:
            logging.error(f"Error fetching releases: {e}")
            return None
        if len(releases) >= num_releases_to_check:
            break
    return releases[:num_releases_to_check]

def download_asset(asset_url, asset_name, token):
    """Downloads a release asset."""
    headers = {"Authorization": f"token {token}", "Accept": "application/octet-stream"}
    try:
        logging.info(f"Downloading asset: {asset_name} from {asset_url}")
        response = requests.get(asset_url, headers=headers, stream=True)
        response.raise_for_status()
        with open(asset_name, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        logging.info(f"Successfully downloaded {asset_name}")
        return asset_name
    except requests.exceptions.RequestException as e:
        logging.error(f"Error downloading asset {asset_name}: {e}")
        return None

def sign_file(gpg, filepath, keyid, passphrase):
    """Signs a file using GPG and creates a detached signature."""
    signature_file = f"{filepath}.asc"
    try:
        logging.info(f"Signing file: {filepath} with key ID {keyid}")
        with open(filepath, 'rb') as f:
            status = gpg.sign_file(f, keyid=keyid, detach=True, output=signature_file, passphrase=passphrase)
        if status.ok:
            logging.info(f"Successfully signed {filepath}, signature: {signature_file}")
            return signature_file
        else:
            logging.error(f"Error signing file {filepath}: {status.status} - {status.stderr}")
            if os.path.exists(signature_file): # Clean up partial signature
                os.remove(signature_file)
            return None
    except Exception as e:
        logging.error(f"Exception during signing of {filepath}: {e}")
        if os.path.exists(signature_file):
            os.remove(signature_file)
        return None

def upload_asset(upload_url_template, filepath, token):
    """Uploads an asset to a GitHub release."""
    asset_name = os.path.basename(filepath)
    # GitHub's upload_url includes path parameters like {?name,label}, remove them.
    upload_url = upload_url_template.split('{')[0] + f"?name={asset_name}"
    headers = {
        "Authorization": f"token {token}",
        "Content-Type": "application/octet-stream"
    }
    try:
        logging.info(f"Uploading asset: {asset_name} to {upload_url}")
        with open(filepath, 'rb') as f:
            response = requests.post(upload_url, headers=headers, data=f)
        response.raise_for_status()
        logging.info(f"Successfully uploaded {asset_name}")
        return response.json()
    except requests.exceptions.RequestException as e:
        logging.error(f"Error uploading asset {asset_name}: {e}")
        if response:
            logging.error(f"Response content: {response.text}")
        return None
    except Exception as e:
        logging.error(f"An unexpected error occurred during upload of {asset_name}: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description="Sign GitHub release artifacts and re-upload them with signatures.")
    parser.add_argument("repo", help="Repository name in 'owner/repo' format (e.g., nightconcept/almandine).")
    parser.add_argument("--github-token", help="GitHub Personal Access Token. If not provided, will try to read from GITHUB_TOKEN env var or prompt.")
    parser.add_argument("--gpg-program", default="gpg", help="Path to GPG executable (if not in PATH).")
    parser.add_argument("--num-releases", type=int, default=5, help="Number of recent releases to process (max 30).")
    parser.add_argument("--skip-already-signed", action='store_true', help="Skip assets if a corresponding signature file already exists in the release.")
    parser.add_argument("--yes", action='store_true', help="Automatically confirm actions without prompting.")

    args = parser.parse_args()

    repo_owner, repo_name = args.repo.split('/')
    num_releases_to_check = min(args.num_releases, 30) # Cap at 30

    github_token = args.github_token or os.environ.get("GITHUB_TOKEN")
    if not github_token:
        github_token = getpass.getpass("Enter GitHub Personal Access Token: ")

    gpg = gnupg.GPG(gpgbinary=args.gpg_program)
    
    # Find the first available GPG secret key suitable for signing
    secret_keys = gpg.list_keys(secret=True)
    signing_key = None
    for key in secret_keys:
        for uid_details in key.get('uids', []):
            # A simple check, might need refinement based on GPG key capabilities
            if 'S' in key.get('cap', ''): # Check if key has signing capability
                signing_key = key
                break
        if signing_key:
            break
            
    if not signing_key:
        logging.error("No suitable GPG secret key found for signing. Please ensure you have a GPG key with signing capability.")
        logging.info("Available secret keys (if any):")
        for skey in secret_keys:
             logging.info(f"  KeyID: {skey['keyid']}, UIDs: {skey.get('uids', 'N/A')}, Capabilities: {skey.get('cap', 'N/A')}")
        return

    gpg_key_id = signing_key['keyid']
    logging.info(f"Using GPG Key ID: {gpg_key_id} ({signing_key.get('uids', ['No UID'])[0]}) for signing.")
    
    gpg_passphrase = getpass.getpass(f"Enter GPG passphrase for key {gpg_key_id} (leave blank if none): ")

    logging.info(f"Fetching last {num_releases_to_check} releases for {repo_owner}/{repo_name}...")
    releases = get_github_releases(repo_owner, repo_name, github_token, num_releases_to_check)

    if not releases:
        logging.info("No releases found or error fetching releases.")
        return

    for release in releases:
        release_name = release.get('name', release['tag_name'])
        logging.info(f"\nProcessing release: {release_name} (ID: {release['id']}, Tag: {release['tag_name']})")
        
        if 'assets' not in release or not release['assets']:
            logging.info(f"No assets found for release {release_name}.")
            continue

        upload_url_template = release['upload_url']
        existing_asset_names = {asset['name'] for asset in release['assets']}

        for asset in release['assets']:
            asset_name = asset['name']
            asset_url = asset['browser_download_url'] # This is the public URL, need API URL for download
            asset_api_url = asset['url'] # API URL for asset details and download

            # Skip if it's already a signature file
            if any(asset_name.endswith(ext) for ext in SIGNATURE_EXTENSIONS):
                logging.info(f"Skipping signature file: {asset_name}")
                continue
            
            # Skip if --skip-already-signed and signature exists
            signature_filename_asc = f"{asset_name}.asc"
            if args.skip_already_signed and signature_filename_asc in existing_asset_names:
                logging.info(f"Signature {signature_filename_asc} already exists for {asset_name}. Skipping.")
                continue

            if not args.yes:
                confirm = input(f"Sign and re-upload asset '{asset_name}' for release '{release_name}'? (y/N): ")
                if confirm.lower() != 'y':
                    logging.info(f"Skipping asset {asset_name} by user choice.")
                    continue
            
            downloaded_file_path = None
            signed_file_path = None
            temp_dir = f"temp_release_assets_{release['id']}"
            os.makedirs(temp_dir, exist_ok=True)
            
            original_asset_path_in_temp = os.path.join(temp_dir, asset_name)

            try:
                downloaded_file_path = download_asset(asset_api_url, original_asset_path_in_temp, github_token)
                if not downloaded_file_path:
                    continue

                signed_file_path = sign_file(gpg, downloaded_file_path, gpg_key_id, gpg_passphrase)
                if not signed_file_path:
                    continue
                
                # Upload original asset (if it was somehow modified or to ensure it's there)
                # This is generally not needed if we are just adding signatures,
                # but could be part of a "refresh" flow. For now, we assume original is fine.
                # If the workflow is to replace, then we'd upload downloaded_file_path.
                # For now, we only upload the signature.

                # Upload signature
                logging.info(f"Uploading signature {os.path.basename(signed_file_path)}...")
                upload_asset(upload_url_template, signed_file_path, github_token)

            finally:
                # Clean up temporary files
                if downloaded_file_path and os.path.exists(downloaded_file_path):
                    os.remove(downloaded_file_path)
                if signed_file_path and os.path.exists(signed_file_path):
                    os.remove(signed_file_path)
                if os.path.exists(temp_dir) and not os.listdir(temp_dir): # Remove dir if empty
                    os.rmdir(temp_dir)
                elif os.path.exists(temp_dir) and os.listdir(temp_dir):
                    logging.warning(f"Temporary directory {temp_dir} is not empty after processing asset {asset_name}. Manual cleanup may be required.")


    logging.info("\nScript finished.")

if __name__ == "__main__":
    main()