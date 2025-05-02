#!/usr/bin/env python3
"""
aws_config_parser.py

Parse aws-config.json and output key configuration values in shell-compatible format.
Usage:
  ./aws_config_parser.py --file aws-config.json --section all
  ./aws_config_parser.py -f aws-config.json -s s3
  ./aws_config_parser.py -f config.json -k region
"""
import json
import argparse
import sys
from pathlib import Path


def load_config(path):
    """
    Load and parse JSON configuration file.
    Raises FileNotFoundError or json.JSONDecodeError.
    """
    with open(path, 'r') as f:
        return json.load(f)


def extract_section(config, section):
    """
    Extract a subsection or a single key from config.
    If section not in config, raise KeyError.
    """
    if section == 'all':
        return config
    if section in config:
        return config[section]
    raise KeyError(f"Section '{section}' not found in configuration.")


def format_shell(vars_dict, prefix=""):
    """
    Format dictionary items as shell variable assignments.
    Example: KEY=value
    """
    lines = []
    for k, v in vars_dict.items():
        # uppercase key and optional prefix
        name = f"{prefix}{k}".upper()
        # convert booleans and numbers to strings
        lines.append(f"{name}='{v}'")
    return lines


def flatten_config(config, parent_key='', sep='_'):
    """
    Flatten nested config dict for shell output.
    E.g., {'s3': {'bucket': 'x'}} -> {'S3_BUCKET': 'x'}
    """
    items = {}
    for k, v in config.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.update(flatten_config(v, new_key, sep=sep))
        else:
            items[new_key] = v
    return items


def main():
    parser = argparse.ArgumentParser(
        description='Parse aws-config.json and emit shell-compatible variables.'
    )
    parser.add_argument(
        '-f', '--file', default='aws-config.json',
        help='Path to aws-config.json file'
    )
    parser.add_argument(
        '-s', '--section', default='all',
        help="Section to extract (e.g., 's3', 'dynamodb', 'api', or 'all')"
    )
    parser.add_argument(
        '-k', '--key', help='Specific config key to output'
    )
    args = parser.parse_args()

    # Load config
    try:
        config = load_config(args.file)
    except FileNotFoundError:
        print(f"Error: Configuration file '{args.file}' not found.", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in '{args.file}': {e}", file=sys.stderr)
        sys.exit(1)

    # Extract section
    try:
        section_data = extract_section(config, args.section)
    except KeyError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # If specific key requested
    if args.key:
        if args.key in section_data:
            value = section_data[args.key]
            print(value)
            sys.exit(0)
        else:
            print(f"Error: Key '{args.key}' not found in section '{args.section}'.", file=sys.stderr)
            sys.exit(1)

    # Flatten and format for shell
    flat = flatten_config(section_data if args.section != 'all' else config)
    shell_lines = format_shell(flat)
    # Print lines
    for line in shell_lines:
        print(line)


if __name__ == '__main__':
    main()
