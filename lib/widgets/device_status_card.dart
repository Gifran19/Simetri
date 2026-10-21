import 'package:flutter/material.dart';

class DeviceStatusCard extends StatelessWidget {
  final bool connected;
  final bool power;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const DeviceStatusCard({
    super.key,
    required this.connected,
    required this.power,
    required this.onChanged,
    this.onConnect,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected
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
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: connected ? const Color(0xff00D9A6) : Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (connected ? const Color(0xff00D9A6) : Colors.redAccent)
                              .withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connected ? 'Perangkat Terhubung' : 'Perangkat Belum Terhubung',
                    style: TextStyle(
                      color: connected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Icon(
                connected ? Icons.wifi : Icons.wifi_off_rounded,
                color: connected ? const Color(0xff00D9A6) : Colors.grey,
                size: 20,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // CONNECTION BUTTON + SWITCH (Row 2)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Tombol di sebelah switch ON/OFF:
              // Saat belum terhubung -> Tombol "Hubungkan Perangkat"
              // Saat sudah terhubung -> Tombol "Perangkat Terhubung" (dengan opsi kelola/putuskan)
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
                              connected ? 'Perangkat Terhubung' : 'Hubungkan Perangkat',
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

              // SWITCH ON/OFF
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    connected && power ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: connected && power ? const Color(0xff00D9A6) : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: connected ? 'Saklar Smart Meter' : 'Hubungkan ke perangkat terlebih dahulu',
                    child: Switch(
                      value: connected && power,
                      activeThumbColor: const Color(0xff00D9A6),
                      activeTrackColor: const Color(0xff00D9A6).withValues(alpha: 0.4),
                      inactiveThumbColor: Colors.grey.shade600,
                      inactiveTrackColor: Colors.white12,
                      onChanged: connected ? onChanged : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
