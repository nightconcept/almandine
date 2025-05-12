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
            next_v_str = "0.2.0-alpha.1"
        else:
            print(f"Error: No existing tags found. Initial bump must be 'alpha' to start with 0.2.0-alpha.1.", file=sys.stderr)
            sys.exit(1)
    else:
        current_v = latest_v # overall latest tag
        if bump_type in ['alpha', 'beta', 'rc']:
            prerelease_token = bump_type
            # Determine the base version for the new prerelease series.
            # This should be the major.minor.patch of the *overall* latest version.
            base_for_series = current_v.finalize_version()

            latest_specific_prerelease = get_latest_prerelease_for_base(tags, base_for_series, prerelease_token)

            if latest_specific_prerelease:
                # An existing prerelease series for this base and token was found. Bump its numeric part.
                # e.g., if latest_specific_prerelease is 0.2.0-alpha.1, next_v becomes 0.2.0-alpha.2
                next_v = latest_specific_prerelease.bump_prerelease()
            else:
                # No existing prerelease series for this base and token type.
                # Start a new one at .1 for this base_for_series.
                # e.g., if base_for_series is 0.2.0 and token is 'alpha', next_v becomes 0.2.0-alpha.1.
                # This correctly handles:
                #   - Starting a new alpha for 0.2.0 if latest_v was 0.2.0 (final).
                #   - Starting a new beta for 0.2.0 (as 0.2.0-beta.1) if latest_v was 0.2.0-alpha.5.
                next_v = base_for_series.replace(prerelease=(prerelease_token, 1))
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
