import 'package:flutter/material.dart';

/// Kartu status perangkat + switch relay.
///
/// - [connected]  : perangkat sudah dipasangkan (pairing) pada aplikasi ini.
/// - [reachable]  : perangkat mengirim telemetri segar (bukan offline).
/// - [relayOn]    : status OUTPUT relay yang DILAPORKAN perangkat
///                  (`relay_output_state`). Bukan bukti kontak relay/beban berubah.
/// - [relayPending]: perintah sudah ditulis, menunggu telemetri konfirmasi.
/// - [canControl] : switch boleh dipakai (perangkat terjangkau, bukan DEMO).
class DeviceStatusCard extends StatelessWidget {
  final bool connected;
  final bool reachable;
  final bool relayOn;
  final bool relayPending;
  final bool canControl;
  final String? statusLabel;
  final String? relayNote;
  final String? deviceId;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const DeviceStatusCard({
    super.key,
    required this.connected,
    required this.relayOn,
    this.reachable = true,
    this.relayPending = false,
    this.canControl = true,
    this.statusLabel,
    this.relayNote,
    this.deviceId,
    required this.onChanged,
    this.onConnect,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final bool online = connected && reachable;
    final Color dotColor = !connected
        ? Colors.redAccent
        : (reachable ? const Color(0xff00D9A6) : Colors.amber);
    final bool switchEnabled = connected && canControl && !relayPending;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: online
              ? const Color(0xff00D9A6).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // STATUS DEVICE (Row 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withValues(alpha: 0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        connected
                            ? (deviceId != null ? 'Smart Meter ($deviceId)' : 'Perangkat Terpasang')
                            : 'Perangkat Belum Terhubung',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: connected ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                online ? Icons.wifi : Icons.wifi_off_rounded,
                color: online ? const Color(0xff00D9A6) : Colors.grey,
                size: 20,
              ),
            ],
          ),

          if (connected && statusLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              statusLabel!,
              style: TextStyle(
                color: reachable ? Colors.white60 : Colors.amber,
                fontSize: 11,
              ),
            ),
          ],

          const SizedBox(height: 14),

          // CONNECTION BUTTON + SWITCH (Row 2)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: connected ? onDisconnect : onConnect,
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: connected
                            ? const Color(0xff00D9A6).withValues(alpha: 0.12)
                            : const Color(0xff007BFF).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: connected
                              ? const Color(0xff00D9A6).withValues(alpha: 0.4)
                              : const Color(0xff007BFF).withValues(alpha: 0.6),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            connected ? Icons.check_circle_rounded : Icons.sensors_rounded,
                            size: 15,
                            color: connected ? const Color(0xff00D9A6) : const Color(0xff00D9FF),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              connected ? 'Perangkat Terpasang' : 'Hubungkan Perangkat',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: connected ? const Color(0xff00D9A6) : Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            connected ? Icons.tune_rounded : Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: connected ? const Color(0xff00D9A6) : Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // SWITCH RELAY (menampilkan status output yang DILAPORKAN perangkat)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (relayPending)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                      ),
                    )
                  else
                    Text(
                      connected && relayOn ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: connected && relayOn ? const Color(0xff00D9A6) : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: !connected
                        ? 'Hubungkan ke perangkat terlebih dahulu'
                        : (relayPending
                            ? 'Menunggu konfirmasi telemetri dari perangkat'
                            : (canControl
                                ? 'Status output relay yang dilaporkan perangkat'
                                : 'Perangkat tidak terjangkau / mode DEMO')),
                    child: Switch(
                      value: connected && relayOn,
                      activeThumbColor: const Color(0xff00D9A6),
                      activeTrackColor: const Color(0xff00D9A6).withValues(alpha: 0.4),
                      inactiveThumbColor: Colors.grey.shade600,
                      inactiveTrackColor: Colors.white12,
                      onChanged: switchEnabled ? onChanged : null,
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (connected && relayNote != null) ...[
            const SizedBox(height: 8),
            Text(
              relayNote!,
              style: const TextStyle(color: Colors.white54, fontSize: 10.5, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}
