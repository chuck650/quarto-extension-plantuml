# Quarto PlantUML Extension Setup Guide

This guide provides the full steps and the final, working Lua filter code to successfully integrate PlantUML diagrams into your Quarto documents, specifically tailored for environments where the standard Pandoc Lua API has known compatibility issues (like the one we debugged).

## 1. Prerequisites Checklist

Ensure the following tools are installed and accessible in your system's PATH.

| **Requirement** | **Purpose** | 
| :--- | :--- |
| **Quarto** | The main document processor. | 
| **Java Runtime** | Required to execute the PlantUML JAR file. | 
| **PlantUML Binary** | The `plantuml` executable (usually installed via a package manager like `dnf` on Fedora). | 

## 2. Project Setup

The filter requires a specific directory structure within your Quarto project folder:

```
my-quarto-project/
├── _extensions/
│   └── plantuml/
│       ├── _extension.yml
│       └── plantuml.lua  <-- The filter file (provided below)
└── document.qmd
```

### File 2a: `_extensions/plantuml/_extension.yml`

Create this file to register the Lua filter with Quarto:

```yaml
title: PlantUML Filter
author: PlantUML Community
version: 1.0.0
filters:
  - plantuml.lua
```


