"""
Setup script for A2A Configuration System.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

with open("pyproject.toml", "r", encoding="utf-8") as fh:
    # Read version from pyproject.toml
    import toml
    pyproject = toml.load(fh)
    version = pyproject["project"]["version"]

setup(
    name="a2a-config",
    version=version,
    author="A2A Team",
    author_email="team@a2a.com",
    description="Configuration system for Craftplan MCP + A2A + elrmcp integration",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/a2a/config",
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
    ],
    python_requires=">=3.8",
    install_requires=[
        "pydantic>=2.0.0",
        "PyYAML>=6.0",
        "toml>=0.10.0",
        "jsonschema>=4.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-asyncio>=0.21.0",
            "black>=23.0.0",
            "ruff>=0.1.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "watching": [
            "watchdog>=3.0.0",
            "aiofiles>=23.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "a2a-config=config.cli:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)