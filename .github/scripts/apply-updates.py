import json
import sys
from pathlib import Path
from ruamel.yaml import YAML

def apply_updates(updates_file: str, pr_body_file: str):
    """
    Parses a JSON file with update information, applies the new versions
    to the corresponding ArgoCD Application YAML files, and generates a
    description for the pull request body.
    """
    try:
        with open(updates_file, 'r', encoding='utf-8') as f:
            updates_data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"Error reading or parsing {updates_file}: {e}", file=sys.stderr)
        sys.exit(1)

    if not updates_data:
        print("No updates to apply.")
        return

    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.indent(mapping=2, sequence=4, offset=2)

    updated_charts_summary = []

    for file_path_str, sources_to_update in updates_data.items():
        file_path = Path(file_path_str)
        if not file_path.is_file():
            print(f"Warning: File not found, skipping: {file_path_str}", file=sys.stderr)
            continue

        with file_path.open('r', encoding='utf-8') as f:
            docs = list(yaml.load_all(f))

        file_was_modified = False
        for doc in docs:
            if (doc and isinstance(doc, dict) and
                    doc.get('kind') == 'Application' and 'spec' in doc and
                    'sources' in doc.get('spec', {})):

                for source_in_file in doc['spec']['sources']:
                    for source_to_update in sources_to_update:
                        if (source_in_file.get('chart') == source_to_update['chart'] and
                                source_in_file.get('repoURL') == source_to_update['repoURL']):
                            
                            old_version = source_in_file.get('targetRevision')
                            new_version = source_to_update['latestVersion']

                            if old_version != new_version:
                                print(f"Updating chart '{source_to_update['chart']}' in '{file_path_str}' from {old_version} to {new_version}")
                                source_in_file['targetRevision'] = new_version
                                file_was_modified = True
                                updated_charts_summary.append(
                                    f"- `{source_to_update['chart']}`: `{old_version}` → `{new_version}`"
                                )
                            break

        if file_was_modified:
            with file_path.open('w', encoding='utf-8') as f:
                yaml.dump_all(docs, f)
    
    pr_body = "Automated PR to update Helm chart dependencies.\n\nThe following charts have been updated:\n\n"
    pr_body += "\n".join(sorted(updated_charts_summary))
    with open(pr_body_file, 'w', encoding='utf-8') as f:
        f.write(pr_body)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python apply-updates.py <updates.json> <pr_body.md>", file=sys.stderr)
        sys.exit(1)
    apply_updates(sys.argv[1], sys.argv[2])