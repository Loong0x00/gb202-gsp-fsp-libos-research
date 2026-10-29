# HSR bounded NVX SRV observer — CPU-only review candidate

This directory is an isolated copy of the current Main `native/`, `adapters/`,
and `protocol/` source needed to build the HSR candidate. Stale build directories
and packaged binaries were not copied. Nothing here was merged, deployed, or run
through Wine, a game, or a GPU.

## Candidate change

The existing CS binding observer is retained for comparison. A second,
diagnostic-only observer now targets the exact DXVK v3.0 interface
`ID3D11VkExtDevice1` IID `cfcf64ef-9586-46d0-bca4-97cf2ca61b06`:

- obtains the interface only from the `ID3D11Device` belonging to the supplied
  game `ID3D11DeviceContext`;
- requires `GetExtensionSupport(D3D11_VK_NVX_IMAGE_VIEW_HANDLE)` where the
  pinned enum value is 5;
- patches only verified vtable slot 6,
  `CreateShaderResourceViewAndGetDriverHandleNVX`, with its exact `bool`
  return and resource/descriptor/SRV-output/`uint32_t`-driver-handle arguments;
- prepares before the one original signed Feature-1 Create, allowing early raw
  creation counts without treating them as current-frame evidence;
- arms exact current Frame motion/depth `IUnknown` identities immediately
  around the one original signed Feature-1 Evaluate;
- calls the predecessor exactly once with unchanged arguments, returns its exact
  result, never writes the driver handle, and inspects only the actual returned
  SRV after a `true` result via `GetDesc` and `GetResource`;
- records actual numeric formats (including raw 34 versus required 37) and only
  accepts exact same-resource 33/37 motion or 19/21 depth contracts;
- keeps at most eight extension-vtable records and eight raw samples per frame;
- uses a read-only atomic slot load, permission-guarded CAS, protection restore,
  predecessor-module lease, and retained context/device/extension COM lifetime.

The NVX report is explicitly logged with `"routing_used":0`. It is not copied
into `FrameSnapshot`'s production view attestation and therefore cannot enable
NR or alter resources, submission, transport, or copyback. A view created while
unarmed, a cached view not returned during the current Evaluate, and a returned
view for any unrelated resource cannot become diagnostic attestation.

## Pinned public-source evidence

The ABI was copied from and checked against the downloaded public source in
`../hsr-nvapi-path/`:

- DXVK v3.0 commit `97fe0c66f89d3c8977578e1b500907306d4af536`;
- dxvk-nvapi commit `46c300bbb8fd15ef208b5f172a719636126729fb`.

The pinned code shows dxvk-nvapi forwarding
`NvAPI_D3D11_CreateShaderResourceView` to this ExtDevice1 method, and DXVK then
calling its concrete `m_device->CreateShaderResourceView`, which can bypass the
standard D3D11 device-vtable observer. The pinned Cubin launch directly emits
`launchCuKernelNVX` with resource arrays and does not call
`CSSetShaderResources`. See `logs/pinned-abi.log` and
`hashes/PINNED_SOURCE_SHA256SUMS`.

This is static path evidence only. The actual current HSR path remains unproven
until a separately authorized physical run observes successful, frame-scoped
NVX calls and exact returned-resource identity matches. Main owns any deployment.

## Verification artifacts

- `logs/cpu-check.log`: clean cross-build, existing CPU tests, 52-check NVX fake
  COM pass-through test, SDK/extension compile-only layout proofs, and PE/source
  checks.
- `logs/pinned-abi.log`: downloaded-source commit/hash/ABI/path verification.
- `patches/hsr-nvx-srv-observer.patch`: source patch relative to Main.
- `hashes/INPUT_SHA256SUMS`: initial isolated Main source copy.
- `hashes/CANDIDATE_SOURCE_SHA256SUMS`: final source tree, excluding build.
- `hashes/BUILD_SHA256SUMS`: candidate DLLs and compile-only layout objects.
