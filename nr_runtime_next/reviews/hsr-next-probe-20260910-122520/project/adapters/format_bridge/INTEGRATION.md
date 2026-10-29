# Main integration sketch

This is a call-order sketch, not a new export or host ABI. It deliberately uses
the existing `D5nRawFrameV1`, `D5rExecuteV1`, and `D5nRawFrameResultV1` types.

## Resource view mapping

Supply the view used by the conversion shader, not merely
`ID3D12Resource::GetDesc().Format`:

```cpp
// WuWa
post.color       = {current_output, DXGI_FORMAT_R11G11B10_FLOAT};
pre.color        = {current_color,  DXGI_FORMAT_R16G16B16A16_FLOAT};
current.motion   = {current_mv,     DXGI_FORMAT_R16G16_FLOAT};
current.depth    = {current_depth,  DXGI_FORMAT_R32_FLOAT};

// HSR shared D3D12 copies; base descs remain TYPELESS.
post.color       = {current_shared_output, DXGI_FORMAT_R11G11B10_FLOAT};
current.motion   = {current_shared_mv,     DXGI_FORMAT_R16G16_SNORM};
current.depth    = {current_shared_depth,
                    DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS};
```

For POST, set `current.game_output = current.color`. The current raw frame's
`source` and `output` must also point to that exact current target, with identical
state declarations. Never fill this from a chain-cached game pointer.

HSR format 33 is the `R16G16_TYPELESS` resource, not the view; view 37 is SNORM.
HSR depth format 19 is the typeless resource; view 21 selects the float depth
plane. Keep `hsr_shared_copy_attested=0` until the exact current D3D11 copies and
GPU-side synchronization are established.

## Dispatch skeleton

```cpp
// raw is the existing adapter-built frame and still names current game/shared
// resources. raw.command_list must equal list.
NormalizePlan plan{};
plan.profile = profile;
plan.pre_sr_color_contract = pre_contract;
plan.same_frame_attested = 1;              // only from real same-frame binding
plan.signed_post_source_attested = is_post_after_successful_signed_evaluate;
plan.hsr_shared_copy_attested = hsr_gpu_copy_and_wait_proven;
plan.expected_nr_calls = control.pass_count;
plan.frame = raw;

NormalizedFrame normalized{};
Status prepare = formats->normalize(plan, list, current, normalized);
if (!prepare) {
    // Do not call native with raw game formats. Continue the original game path.
    publish_bypass_reason(prepare);
    return_original_result();
}

D5rExecuteV1 request = existing_request;
request.frame = normalized.frame;           // insert before valid_frame()
D5nRawFrameResultV1 result{};
const uint32_t runtime_ok = runtime_execute(&request, &result);

CommitOutput committed{};
Status commit_status{};
if (runtime_ok && result.status == D5N_FRAME_EVALUATED_V1) {
    commit_status = formats->commit(normalized.token, list, result, committed);
}

if (is_post) {
    // Game output changed only if this is true. Native ERROR/CREATE_PENDING and
    // commit rejection leave current.game_output untouched.
    const bool changed = commit_status && committed.output_committed == 1;
    acknowledge_output_committed(changed);
} else {
    // PRE ordinary SR only. Use replacement for this exact original Evaluate;
    // otherwise leave the game's original Color parameter untouched.
    if (commit_status && committed.pre_sr_color)
        set_original_sr_color_for_this_call(committed.pre_sr_color,
                                            committed.pre_sr_color_state);
}

// Close and execute the list. Signal an external fence strictly after this list.
queue->ExecuteCommandLists(...);
queue->Signal(fence, value);
formats->submitted(normalized.token, queue, fence, value);
```

`CREATE_PENDING`, `ERROR`, disabled, or any other non-EVALUATED result still has
recorded prepare/native commands. If that list executes, call `submitted()` and
retire by fence even though `commit()` was not called. If the list is reset and
never submitted, call `abandon_unsubmitted(token)` after Reset is certain.

A successful PRE replacement remains native-owned; do not release it through the
format bridge. Restore every original NGX parameter after the original Evaluate.
A successful POST `D5nFrameCommitV1::output_committed` must reflect the bridge
commit, not just `result.status`.

The bridge's compute state is not queryable/restorable in D3D12. Rebind the host's
own descriptor heaps/root signature/PSO before subsequent compute work.

## HSR D3D11 handoff

The bridge begins only after a future transport has:

1. copied the one coherent Output/MV/depth set to current shared D3D12 resources;
2. signaled its D3D11 shared fence; and
3. queued a D3D12 GPU `Wait` before this command list.

After POST conversion, signal the D3D12 shared fence, queue a D3D11 GPU wait, and
copy the shared R11 result to the current D3D11 Output. Do not use the old
render-thread `WaitForSingleObject` pattern. The real HSR pre-Color and
float16-replacement contract remain unknown, so do not advertise HSR PRE from
this bridge alone.
