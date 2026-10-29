# Native signed-RR replay capture — valid but ends before target close-up

- Raw payload: /home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/dlss5-raw-captures/20260903-121233-717-p324
- 75/75/75 complete, abandoned=0, write_failed=0.
- 225 raw files, 10,657,591,200 bytes; every file size and SHA-256 verified.
- Global frame IDs 2849..2923 are contiguous; 75 matching Router records all show signed RR success, requested/effective mode 0, post_called=0, native_capture_called=1.
- Exact raw QPC duration: 2.4656223 s; all frames are 6144x3456 native RR plus 3564x2005 motion/depth.
- OBS SHA-256: 15113cae1396e3437af7b82a5b71fddb25eee88b5d42154e259d0f484b13b23e; full AV1 decode passed.
- Raw ended around OBS t=6.168 s. The R cinematic first appears around OBS t=6.250 s, about 82 ms later, so this capture is a valid pre-event temporal baseline but does not contain the decisive close-up.
- The recorder was therefore expanded to a hard-bounded 150-frame / 24-GiB variant for the next capture.
