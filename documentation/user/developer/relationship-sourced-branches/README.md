# Relationship-sourced branches — developer documentation

A `parallel_step` `branch` can be sourced from a relationship
(`branch :jobs, relationship: :jobs`) instead of a fixed `resource`, so the
fan-out is runtime-sized by the rows the relationship returns rather than the
number of branch entities declared at compile time. The
`IntegrateParallelRegions` transformer passes that relationship source through
to a dynamic `ash_state_machine` parallel region, where the actual branch count
— and the `{:require_n, n}` bound — is resolved at runtime.

```mermaid
flowchart LR
  rel[":jobs relationship"] --> branch["branch :jobs"]
  branch --> trans["IntegrateParallelRegions"]
  trans --> region["dynamic SM parallel_region"]
  region --> fanout["runtime-sized fan-out"]
```

## Stories

| ID        | Story                                                                            | File                                                              |
| --------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| US-RSB-01 | Declare a `branch` sourced from a relationship instead of a fixed resource       | [US-RSB-01](./US-RSB-01-declare-relationship-branch.md)           |
| US-RSB-02 | The branch passes its relationship/needs through to the state-machine region     | [US-RSB-02](./US-RSB-02-passthrough-to-region.md)                 |
| US-RSB-03 | `resource` is not required when a relationship source is given                   | [US-RSB-03](./US-RSB-03-resource-not-required.md)                 |
| US-RSB-04 | `{:require_n, n}` is no longer rejected at compile time for a dynamic branch     | [US-RSB-04](./US-RSB-04-require-n-runtime.md)                     |
| US-RSB-05 | A static `branch :name, Resource` still compiles and runs unchanged              | [US-RSB-05](./US-RSB-05-static-branch-backcompat.md)              |
| US-RSB-06 | A relationship-sourced parallel step finalizes its parent when branches complete | [US-RSB-06](./US-RSB-06-parent-finalizes-on-branch-completion.md) |

## See also

- [needs-gated-dag RFC](../../../rfc/needs-gated-dag.md)
- [dynamic-parallel-regions RFC](../../../../../ash_state_machine/documentation/rfc/dynamic-parallel-regions.md)
- [Workflow DAG engine plan](../../../../../../documentation/plans/workflow-dag-engine.md)
