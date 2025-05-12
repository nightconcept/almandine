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

def get_latest_prerelease_for_base(tags, base_version, token):
    """
    Finds the latest prerelease tag for a given base version and token.
    Example: base_version = 0.2.0, token = 'alpha' -> finds latest v0.2.0-alpha.N
    Returns a semver.VersionInfo object or None.
    """
    latest_prerelease_v = None
    for tag_str in reversed(tags): # Assumes tags are sorted v:refname
        try:
            v = semver.VersionInfo.parse(tag_str[1:])
            if v.major == base_version.major and \
               v.minor == base_version.minor and \
               v.patch == base_version.patch and \
               v.prerelease and len(v.prerelease) == 2 and v.prerelease[0] == token:
                # Compare numeric part of the prerelease
                if latest_prerelease_v is None or v.prerelease[1] > latest_prerelease_v.prerelease[1]:
                    latest_prerelease_v = v
        except ValueError:
            # Not a valid semver tag or unexpected prerelease format
            continue
        except TypeError:
            # Handle cases where prerelease[1] might not be comparable (e.g., not an int)
            print(f"Warning: Prerelease part of tag {tag_str} is not as expected for comparison.", file=sys.stderr)
            continue
    return latest_prerelease_v

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
            next_v = semver.VersionInfo(0, 2, 0, prerelease='alpha.1')
            # Check for existing tags and bump if necessary
            temp_next_v_tag = f"v{str(next_v)}"
            while temp_next_v_tag in tags: # 'tags' contains all existing v* tags
                next_v = next_v.bump_prerelease(token='alpha')
                temp_next_v_tag = f"v{str(next_v)}"
            next_v_str = str(next_v)
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
                next_v = semver.VersionInfo(current_v.major, current_v.minor, current_v.patch, prerelease='alpha.1')

            # Check for existing tags and bump if necessary
            temp_next_v_tag = f"v{str(next_v)}"
            while temp_next_v_tag in tags:
                next_v = next_v.bump_prerelease(token='alpha') # Bumps 'alpha.1' to 'alpha.2', etc.
                temp_next_v_tag = f"v{str(next_v)}"
            next_v_str = str(next_v)
        elif bump_type == 'beta':
            if current_v.prerelease and current_v.prerelease[0] == 'beta':
                next_v = current_v.bump_prerelease(token='beta')
            else: # New beta series, must come from alpha or be a new beta for a version
                # e.g., 0.1.0-alpha.2 -> 0.1.0-beta.1
                next_v = semver.VersionInfo(current_v.major, current_v.minor, current_v.patch, prerelease='beta.1')

            # Check for existing tags and bump if necessary
            temp_next_v_tag = f"v{str(next_v)}"
            while temp_next_v_tag in tags:
                next_v = next_v.bump_prerelease(token='beta')
                temp_next_v_tag = f"v{str(next_v)}"
            next_v_str = str(next_v)
        elif bump_type == 'rc':
            if current_v.prerelease and current_v.prerelease[0] == 'rc':
                next_v = current_v.bump_prerelease(token='rc')
            else: # New RC series
                next_v = semver.VersionInfo(current_v.major, current_v.minor, current_v.patch, prerelease='rc.1')

            # Check for existing tags and bump if necessary
            temp_next_v_tag = f"v{str(next_v)}"
            while temp_next_v_tag in tags:
                next_v = next_v.bump_prerelease(token='rc')
                temp_next_v_tag = f"v{str(next_v)}"
            next_v_str = str(next_v)
        elif bump_type == 'promote_to_final':
            if not current_v.prerelease:
                print(f"Error: Version {current_v} is already final. Cannot promote.", file=sys.stderr)
                sys.exit(1)
            next_v = current_v.finalize_version()
            next_v_str = str(next_v)
            is_prerelease = "false"
        elif bump_type == 'patch':
            # For patch, minor, major, we always bump from the finalized version of the *overall* latest tag.
            base_v = current_v.finalize_version()
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
