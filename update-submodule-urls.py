#!/usr/bin/env python3
"""
Script to replace submodule URLs in git history using git-filter-repo.
This script rewrites all commits to replace old gitee.com URLs with new gitlink.org.cn URLs.
"""

import sys
import os
import subprocess
import argparse

try:
    import git_filter_repo as fr
except ImportError:
    print("ERROR: git-filter-repo not found. Install it with: pip install git-filter-repo", file=sys.stderr)
    sys.exit(1)

# URL mappings
NEW_URL = b"https://gitlink.org.cn/vChewing/vChewing-VanguardLexicon.git"
OLD_URLS = [
    b"https://gitee.com/vChewing/libvchewing-data.git",
    b"https://gitee.com/vChewing/libvchewing-data",
    b"http://gitee.com/vChewing/libvchewing-data.git",
    b"http://gitee.com/vChewing/libvchewing-data",
    b"git@gitee.com:vChewing/libvchewing-data.git",
    b"git://gitee.com/vChewing/libvchewing-data",
]


class SubmoduleURLRewriter:
    """Rewrites submodule URLs in git history"""
    
    def __init__(self):
        self.blob_replacements = {}
        self.replacement_count = 0
    
    def blob_callback(self, blob, metadata):
        """Process each blob and replace URLs"""
        original_data = blob.data
        new_data = original_data
        
        # Replace all old URLs with new URL
        for old_url in OLD_URLS:
            if old_url in new_data:
                new_data = new_data.replace(old_url, NEW_URL)
                self.replacement_count += 1
        
        # Update blob data if changed
        if new_data != original_data:
            blob.data = new_data
            # Store mapping for debugging
            self.blob_replacements[blob.original_id] = (original_data[:100], new_data[:100])


def process_repository(repo_path):
    """Process a single repository"""
    print(f"\n{'='*60}")
    print(f"Processing repository: {repo_path}")
    print('='*60)
    
    # Verify it's a git repository
    git_dir = os.path.join(repo_path, '.git')
    if not os.path.exists(git_dir):
        print(f"ERROR: Not a git repository: {repo_path}", file=sys.stderr)
        return False
    
    # Change to repository directory
    os.chdir(repo_path)
    
    # Create rewriter instance
    rewriter = SubmoduleURLRewriter()
    
    print("[INFO] Running git-filter-repo to rewrite history...")
    
    try:
        # Set up filter arguments
        args = fr.FilteringOptions.parse_args(['--force', '--quiet'])
        
        # Create filter with blob callback
        filter_obj = fr.RepoFilter(args, blob_callback=rewriter.blob_callback)
        
        # Run the filter
        filter_obj.run()
        
        print(f"[INFO] Replaced URLs in {rewriter.replacement_count} blobs")
        
        # Update working tree
        print("[INFO] Updating working tree...")
        subprocess.run(['git', 'checkout', 'HEAD'], capture_output=True, check=False)
        
        # Sync submodules
        print("[INFO] Syncing submodules...")
        subprocess.run(['git', 'submodule', 'sync', '--recursive'], capture_output=True, check=False)
        
        # Verify changes
        print("[INFO] Verifying changes...")
        result = subprocess.run(
            ['git', 'grep', '-n', 'gitee.com/vChewing/libvchewing-data', '--', '.gitmodules'],
            capture_output=True
        )
        
        if result.returncode == 0:
            print(f"[WARN] Leftover gitee URL found in .gitmodules:", file=sys.stderr)
            print(result.stdout.decode(), file=sys.stderr)
        else:
            print("[OK] Successfully replaced all URLs")
        
        # Run garbage collection
        print("[INFO] Running git gc to clean up repository...")
        subprocess.run(['git', 'reflog', 'expire', '--expire=now', '--all'], capture_output=True, check=False)
        subprocess.run(['git', 'gc', '--prune=now', '--aggressive'], capture_output=True, check=False)
        
        print(f"[OK] Repository {repo_path} processed successfully!")
        print("[INFO] To push the rewritten history, run:")
        print("       git push --force-with-lease --all")
        print("       git push --force-with-lease --tags")
        
        return True
        
    except Exception as e:
        print(f"[ERROR] Failed to process {repo_path}: {e}", file=sys.stderr)
        return False


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Replace submodule URLs in git repository history'
    )
    parser.add_argument(
        'repositories',
        nargs='+',
        help='Path(s) to git repository/repositories to process'
    )
    
    args = parser.parse_args()
    
    # Check git is available
    try:
        subprocess.run(['git', '--version'], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("ERROR: git not found. Please install git first.", file=sys.stderr)
        sys.exit(1)
    
    # Process each repository
    success_count = 0
    for repo_path in args.repositories:
        # Resolve to absolute path
        abs_path = os.path.abspath(repo_path)
        
        if process_repository(abs_path):
            success_count += 1
    
    print(f"\n{'='*60}")
    print(f"Processed {success_count}/{len(args.repositories)} repositories successfully")
    print('='*60)
    
    sys.exit(0 if success_count == len(args.repositories) else 1)


if __name__ == '__main__':
    main()
