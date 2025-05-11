import os
import subprocess
import semver
import sys

def get_tags():
    try:
        result = subprocess.run(['git', 'tag', '-l', 'v*', '--sort=v:refname'], capture_output=True, text=True, check=True)
        tags = result.stdout.strip().split('\n')
        return [tag for tag in tags if tag] # Filter out empty strings if any
    except subprocess.CalledProcessError as e:
        print(f"Error fetching tags: {e}", file=sys.stderr)
        return []

def get_latest_semver(tags):
    latest_v = None
    for tag_str in reversed(tags): # Iterate from newest to oldest based on git sort
        try:
            v = semver.VersionInfo.parse(tag_str[1:]) # Remove 'v' prefix
            if latest_v is None or v > latest_v:
                latest_v = v
        except ValueError:
            # Not a valid semver tag, skip
            continue
    return latest_v

def main():
    bump_type = os.environ.get('BUMP_TYPE')
    if not bump_type:
        print("Error: BUMP_TYPE environment variable not set.", file=sys.stderr)
        sys.exit(1)

    tags = get_tags()
    latest_v = get_latest_semver(tags)

    next_v_str = ""
    is_prerelease = "true"

    if not latest_v:
        if bump_type == 'alpha':
            next_v_str = "0.2.0-alpha.1"
        else:
            print(f"Error: No existing tags found. Initial bump must be 'alpha' to start with 0.2.0-alpha.1.", file=sys.stderr)
            sys.exit(1)
    else:
        current_v = latest_v
        if bump_type == 'alpha':
            if current_v.prerelease and current_v.prerelease[0] == 'alpha':
                next_v = current_v.bump_prerelease(token='alpha')
            else: # New alpha series for current major.minor.patch or next patch
                # If current is final (e.g. 0.1.0), new alpha is 0.1.0-alpha.1
                # If current is rc (e.g. 0.1.0-rc.1), new alpha is 0.1.0-alpha.1
                # If current is beta (e.g. 0.1.0-beta.1), new alpha is 0.1.0-alpha.1
                next_v = semver.VersionInfo(current_v.major, current_v.minor, current_v.patch, prerelease=('alpha', 1))
            next_v_str = str(next_v)
        elif bump_type == 'beta':
            if current_v.prerelease and current_v.prerelease[0] == 'beta':
                next_v = current_v.bump_prerelease(token='beta')
            else: # New beta series, must come from alpha or be a new beta for a version
                # e.g., 0.1.0-alpha.2 -> 0.1.0-beta.1
                next_v = semver.VersionInfo(current_v.major, current_v.minor, current_v.patch, prerelease=('beta', 1))
            next_v_str = str(next_v)
        elif bump_type == 'rc':
            if current_v.prerelease and current_v.prerelease[0] == 'rc':
                next_v = current_v.bump_prerelease(token='rc')
            else: # New RC series
                next_v = semver.VersionInfo(current_v.major, current_v.minor, current_v.patch, prerelease=('rc', 1))
            next_v_str = str(next_v)
        elif bump_type == 'promote_to_final':
            if not current_v.prerelease:
                print(f"Error: Version {current_v} is already final. Cannot promote.", file=sys.stderr)
                sys.exit(1)
            next_v = current_v.finalize_version()
            next_v_str = str(next_v)
            is_prerelease = "false"
        elif bump_type == 'patch':
            base_v = current_v.finalize_version() # Ensure we bump from a stable part
            next_v = base_v.bump_patch()
            next_v_str = str(next_v)
            is_prerelease = "false"
        elif bump_type == 'minor':
            base_v = current_v.finalize_version()
            next_v = base_v.bump_minor()
            next_v_str = str(next_v)
            is_prerelease = "false"
        elif bump_type == 'major':
            base_v = current_v.finalize_version()
            next_v = base_v.bump_major()
            next_v_str = str(next_v)
            is_prerelease = "false"
        else:
            print(f"Error: Unknown BUMP_TYPE '{bump_type}'", file=sys.stderr)
            sys.exit(1)

    if not next_v_str.startswith('v'):
        next_v_tag = f"v{next_v_str}"
    else:
        next_v_tag = next_v_str


    print(f"Calculated next version: {next_v_tag}", file=sys.stderr)
    print(f"::set-output name=next_version::{next_v_tag}")
    print(f"::set-output name=is_prerelease::{is_prerelease}")

if __name__ == "__main__":
    main()
