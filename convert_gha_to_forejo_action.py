import os
import sys
from ruamel.yaml import YAML

# Documentation links
FORGEJO_DOCS = "https://forgejo.org/docs/latest/user/actions/"
CODEBERG_RUNNER_DOCS = "https://codeberg.org/actions/meta"

def fix_workflow(file_path):
    # Use 'rt' (round-trip) to preserve comments and formatting
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096  # Avoid wrapping
    
    # Configure indentation to match common GitHub Action styles (2 for maps, 4 for sequences)
    yaml.indent(mapping=2, sequence=4, offset=2)
    
    try:
        with open(file_path, 'r') as f:
            data = yaml.load(f)
    except Exception as e:
        print(f"Error loading {file_path}: {e}", file=sys.stderr)
        return False, []

    if not data:
        return False, []

    changes = []

    # 1. Handle Concurrency (Supported)
    if 'concurrency' in data:
        msg = f"Supported in Forgejo. (Docs: {FORGEJO_DOCS})"
        data.yaml_set_comment_before_after_key('concurrency', before=msg)
        changes.append("Added note about concurrency support")

    # 2. Handle Permissions (Ignored)
    if 'permissions' in data:
        msg = f"Permissions key is currently IGNORED by Forgejo. GITHUB_TOKEN has write access by default. (Docs: {FORGEJO_DOCS})"
        data.yaml_set_comment_before_after_key('permissions', before=msg)
        changes.append("Added note about ignored permissions")

    # 3. Handle Jobs (Runners and Actions)
    if 'jobs' in data:
        for job_id, job in data['jobs'].items():
            # Fix runs-on
            if 'runs-on' in job:
                runs_on = str(job['runs-on'])
                if 'blacksmith-4vcpu' in runs_on:
                    job['runs-on'] = 'codeberg-medium'
                    job.yaml_add_eol_comment(f"MODIFIED: Blacksmith 4vcpu -> codeberg-medium (Docs: {CODEBERG_RUNNER_DOCS})", 'runs-on')
                    changes.append(f"Job '{job_id}': Blacksmith 4vcpu -> codeberg-medium")
                elif 'blacksmith' in runs_on:
                    job['runs-on'] = 'codeberg-small'
                    job.yaml_add_eol_comment(f"MODIFIED: Blacksmith -> codeberg-small (Docs: {CODEBERG_RUNNER_DOCS})", 'runs-on')
                    changes.append(f"Job '{job_id}': Blacksmith -> codeberg-small")
                elif 'ubuntu-latest' in runs_on:
                    job['runs-on'] = 'codeberg-small'
                    job.yaml_add_eol_comment(f"MODIFIED: ubuntu-latest -> codeberg-small (Docs: {CODEBERG_RUNNER_DOCS})", 'runs-on')
                    changes.append(f"Job '{job_id}': ubuntu-latest -> codeberg-small")

            # Fix Environment
            if 'environment' in job:
                msg = f"Partial support; GitHub-style protection rules and manual approvals are not implemented. (Docs: {FORGEJO_DOCS})"
                job.yaml_set_comment_before_after_key('environment', before=msg)
                changes.append(f"Job '{job_id}': Added environment support note")

            # Fix Steps
            if 'steps' in job:
                for step in job['steps']:
                    if 'uses' in step:
                        uses = step['uses']
                        # Blacksmith Actions
                        if 'useblacksmith/setup-node' in uses:
                            step['uses'] = 'actions/setup-node@v4'
                            step.yaml_add_eol_comment("MODIFIED: Replaced Blacksmith action", 'uses')
                            changes.append(f"Job '{job_id}': Replaced setup-node")
                        elif 'useblacksmith/setup-python' in uses:
                            step['uses'] = 'actions/setup-python@v5'
                            step.yaml_add_eol_comment("MODIFIED: Replaced Blacksmith action", 'uses')
                            changes.append(f"Job '{job_id}': Replaced setup-python")
                        
                        # Artifacts Standardization
                        elif 'actions/upload-artifact@v' in uses and not uses.endswith('@v4'):
                            # Simple check for v5+
                            ver_part = uses.split('@v')[-1]
                            if ver_part.isdigit() and int(ver_part) > 4:
                                step['uses'] = 'actions/upload-artifact@v4'
                                step.yaml_add_eol_comment("MODIFIED: Downgraded to v4 for Codeberg", 'uses')
                                changes.append(f"Job '{job_id}': Downgraded upload-artifact")
                        elif 'actions/download-artifact@v' in uses and not uses.endswith('@v4'):
                            ver_part = uses.split('@v')[-1]
                            if ver_part.isdigit() and int(ver_part) > 4:
                                step['uses'] = 'actions/download-artifact@v4'
                                step.yaml_add_eol_comment("MODIFIED: Downgraded to v4 for Codeberg", 'uses')
                                changes.append(f"Job '{job_id}': Downgraded download-artifact")
                        
                        # GitHub Script
                        elif 'actions/github-script' in uses:
                            msg = f"Supported for REST API; GraphQL is NOT supported in Forgejo. (Docs: {FORGEJO_DOCS})"
                            step.yaml_add_eol_comment(msg, 'uses')
                            changes.append(f"Job '{job_id}': Added github-script limitation note")

    if changes:
        with open(file_path, 'w') as f:
            yaml.dump(data, f)
        return True, changes
    return False, []

def main():
    this_script = os.path.basename(__file__)
    files = [f for f in os.listdir('.') if (f.endswith('.yml') or f.endswith('.yaml')) and f != this_script]
    print(f"--- Running Codeberg Migration Script (ruamel.yaml) ---")
    
    for file in files:
        changed, changes_made = fix_workflow(file)
        if changed:
            print(f"Fixed {file}:")
            for change in changes_made:
                print(f"  - {change}")
        else:
            print(f"No changes needed for {file}")

if __name__ == "__main__":
    main()
