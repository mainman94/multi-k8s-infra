# c:\Users\p.hauptmann\work\phm.me_cluster\traefik-reverse-proxy\argocd-apps\argocd\extract_repos.py
import yaml
import argparse
import json
from pathlib import Path
import sys
from typing import List, Dict, Optional, Any

import requests
from packaging.version import parse as parse_version, InvalidVersion


def extract_repo_info(file_path: Path) -> Optional[List[Dict[str, str]]]:
    """
    Reads a YAML file, parsing all documents within it. It extracts source
    information from any ArgoCD Application resources where a source
    explicitly defines a 'chart'.

    If matching sources are found, it returns a list of dictionaries, each
    containing 'repoURL', 'targetRevision', and 'chart'.
    Otherwise, it returns None.

    Args:
        file_path (Path): The path object for the YAML file.

    Returns:
        An optional list of source dictionaries, or None if no applicable
        chart-based sources are found.
    """
    try:
        with file_path.open('r', encoding='utf-8') as stream:
            # Use safe_load_all to handle multi-document YAML files
            documents = yaml.safe_load_all(stream)
            chart_based_sources = []

            for data in documents:
                # Check for valid data and the expected ArgoCD Application structure
                if (data and isinstance(data, dict) and
                        data.get('kind') == 'Application' and 'spec' in data and
                        'sources' in data['spec']):
                    # Ensure 'sources' is a list before iterating and find sources with a chart
                    if isinstance(data['spec']['sources'], list):
                        for source in data['spec']['sources']:
                            if 'chart' in source:
                                chart_based_sources.append({
                                    'repoURL': source.get('repoURL', 'Not specified'),
                                    'chart': source.get('chart', 'Not specified'),
                                    'targetRevision': source.get('targetRevision', 'Not specified')
                                })
            return chart_based_sources if chart_based_sources else None
    except yaml.YAMLError as exc:
        print(f"Warning: Could not parse YAML file '{file_path}': {exc}", file=sys.stderr)
    except Exception as e:
        print(f"Warning: An unexpected error occurred with file '{file_path}': {e}", file=sys.stderr)
    
    return None

# A simple cache to avoid re-downloading the same repo index file
_repo_index_cache: Dict[str, Any] = {}

def get_latest_chart_version(repo_url: str, chart_name: str) -> Optional[str]:
    """
    Fetches a Helm repository's index and finds the latest version of a chart.
    Results are cached in memory to avoid redundant network requests.
    """
    if repo_url in _repo_index_cache:
        index_data = _repo_index_cache[repo_url]
    else:
        index_url = f"{repo_url.rstrip('/')}/index.yaml"
        try:
            response = requests.get(index_url, timeout=10)
            response.raise_for_status()  # Raises an HTTPError for bad responses (4xx or 5xx)
            index_data = yaml.safe_load(response.content)
            _repo_index_cache[repo_url] = index_data
        except (requests.RequestException, yaml.YAMLError) as e:
            print(f"Warning: Could not fetch or parse index for repo '{repo_url}': {e}", file=sys.stderr)
            _repo_index_cache[repo_url] = None # Cache failure to avoid retries
            return None

    if not index_data or chart_name not in index_data.get('entries', {}):
        print(f"Warning: Chart '{chart_name}' not found in repository '{repo_url}'.", file=sys.stderr)
        return None

    versions = []
    for release in index_data['entries'][chart_name]:
        try:
            v = parse_version(release['version'])
            # Nur stabile Versionen (keine Pre-Releases) berücksichtigen
            if not v.is_prerelease:
                versions.append(v)
        except InvalidVersion:
            continue # Skip malformed version strings

    return str(max(versions)) if versions else None

def main():
    """
    Main function to parse arguments, find YAML files, and print repo info.
    """
    parser = argparse.ArgumentParser(
        description="Recursively search for *.yaml or *.yml files, find ArgoCD applications "
                    "using Helm charts, and check for newer chart versions."
    )
    parser.add_argument(
        "search_paths",
        nargs='+',
        help="One or more directory paths to search recursively."
    )
    args = parser.parse_args()

    all_results = {}
    found_checkable_sources = False
    for base_path_str in args.search_paths:
        base_path = Path(base_path_str)
        if not base_path.is_dir():
            print(f"Warning: Path '{base_path}' is not a valid directory. Skipping.", file=sys.stderr)
            continue

        # Find all .yaml and .yml files recursively
        yaml_files = list(base_path.rglob("*.yaml")) + list(base_path.rglob("*.yml"))

        for file_path in yaml_files:
            sources = extract_repo_info(file_path)
            if sources:
                found_checkable_sources = True
                processed_sources = []
                for source in sources:
                    current_version_str = source['targetRevision']
                    latest_version_str = get_latest_chart_version(source['repoURL'], source['chart'])

                    update_info = {
                        "latestVersion": "N/A",
                        "updateAvailable": False
                    }

                    if latest_version_str:
                        update_info["latestVersion"] = latest_version_str
                        try:
                            # Compare versions if the current version is a valid SemVer
                            current_v = parse_version(current_version_str)
                            latest_v = parse_version(latest_version_str)
                            if latest_v > current_v:
                                update_info["updateAvailable"] = True
                        except InvalidVersion:
                            # Cannot compare versions if current is not valid (e.g., "HEAD")
                            pass

                    if update_info["updateAvailable"]:
                        processed_sources.append({**source, **update_info})
                if processed_sources:
                    # Use as_posix() to ensure forward slashes for cross-platform consistency in the JSON output
                    all_results[file_path.resolve().as_posix()] = processed_sources

    # Always print the final aggregated results as a JSON object.
    # If no updates are found, it will be an empty object: {}
    print(json.dumps(all_results, indent=2))

if __name__ == "__main__":
    main()
