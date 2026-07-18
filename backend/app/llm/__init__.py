"""Safe, validated LLM processing boundary.

The package deliberately does not import persistence modules at import time so
its schema and routing tests can run before the backend-core branch is merged.
"""
