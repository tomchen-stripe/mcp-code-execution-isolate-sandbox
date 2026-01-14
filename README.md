# MCP Code Execution Sandbox with IOI Isolate

Sandboxed execution environment for MCP Clients (ChatGPT, Gemini, Claude) to execute code on Stripe's servers using IOI Isolate.

Related reading:

* [https://blog.cloudflare.com/code-mode/](https://blog.cloudflare.com/code-mode/)
* [https://www.anthropic.com/engineering/code-execution-with-mcp](https://www.anthropic.com/engineering/code-execution-with-mcp)
* [go/scaling-mcp](https://docs.google.com/document/d/1YyzD3A_110F1gHU4EcBNXBhVdTVw4zPLtD0NNAqKPhM/edit?tab=t.0)
* [go/mcp-code-execution](http://go/mcp-code-execution)

## Problem

MCP (Model Context Protocol) clients generate and execute code based on LLM outputs. This code is untrusted and requires isolation to prevent:
- Filesystem access to sensitive data (source code, credentials, user files)
- Unrestricted network access to internal services
- Resource exhaustion (CPU, memory)
- Privilege escalation

## Solution

IOI Isolate provides lightweight Linux kernel-based sandboxing via namespaces and cgroups.

### Isolation Guarantees

- **Filesystem**: Only `/box` (sandbox workspace) accessible, host filesystem blocked
- **Network**: Disabled by default, optional proxy-only access via `--share-net`
- **Resources**: Hard limits on CPU time, memory, wall-clock time
- **Execution**: setuid root binary, minimal attack surface

### Docker vs Isolate

| Feature | Docker | Isolate |
|---------|--------|---------|
| Startup time | 1-2+ seconds | < 0.1 seconds |
| Memory overhead | ~100+ MB | < 1 MB |
| Architecture | Daemon + runtime + containers | Single setuid binary |
| Use case | Service containerization | Untrusted code execution |
| CPU time limits | Approximate | Precise (kernel-level) |
| Complexity | High (images, layers, volumes) | Low (CLI flags) |

**For short-lived, untrusted code execution: Isolate is better.**

## Architecture

```
┌─────────────────────────────────────────────┐
│ MCP Client (LLM-generated code)             │
└─────────────────┬───────────────────────────┘
                  │
          ┌───────▼────────┐
          │ run-sandbox.sh │
          └───────┬────────┘
                  │
          ┌───────▼────────┐
          │ IOI Isolate    │ (setuid root)
          └───────┬────────┘
                  │
    ┌─────────────▼──────────────┐
    │ Linux Kernel               │
    │ - Namespaces (filesystem)  │
    │ - Cgroups (resources)      │
    │ - Network isolation        │
    └────────────────────────────┘
```

## Example

With network enabled (`SHARE_NET=1`), sandboxed code can access Stripe API through egress proxy:

```bash
SHARE_NET=1 ./run-sandbox.sh test-stripe.js
```

Verify yourself that the isolate doesn't have access to the parents filesystem:

```bash
./run-sandbox.sh test-isolate.js

```

Runtime: ~0.2 seconds including Node.js startup and API call.

## Installation & Testing

See [INSTALL.md](INSTALL.md) for complete setup instructions.

## References

- [IOI Isolate](https://github.com/ioi/isolate) - Sandbox for programming contests
- [Isolate Paper](https://mj.ucw.cz/papers/isolate.pdf) - Design and implementation
