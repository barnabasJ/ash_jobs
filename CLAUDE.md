# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

`ash_jobs` is an Elixir library project. The codebase is currently in early
stages with minimal implementation.

## Development Commands

### Dependencies

```bash
mix deps.get          # Install dependencies
mix deps.update --all # Update all dependencies
```

### Testing

```bash
mix test              # Run all tests
mix test <file>       # Run a specific test file
mix test <file>:<line> # Run a specific test at line number
```

### Code Quality

```bash
mix format            # Format code according to .formatter.exs
mix format --check-formatted # Check if code is properly formatted
```

### Compilation

```bash
mix compile           # Compile the project
mix clean             # Clean build artifacts
```

### Documentation

```bash
mix docs              # Generate documentation (requires ex_doc dependency)
```

### Interactive Development

```bash
iex -S mix            # Start IEx with the project loaded
```

## Project Structure

```
ash_jobs/
├── lib/              # Source code
│   └── ash_jobs.ex   # Main module
├── test/             # Test files
│   ├── test_helper.exs
│   └── ash_jobs_test.exs
└── mix.exs           # Project configuration
```

## Architecture Notes

This project is in early development. Architecture patterns will emerge as the
codebase grows. The name suggests this will be a job/background task processing
library related to the Ash Framework ecosystem.

## Development Workflow

When adding new functionality:

1. Write tests first in the `test/` directory
2. Implement functionality in `lib/`
3. Run `mix format` before committing
4. Ensure `mix test` passes
