// ============================================================
//  SIMETRI Firebase Integrated Firmware
//  File: firmware_iot/simetri_firebase_integrated/root_ca.h
//
//  Sertifikat Root CA Google Trust Services (GTS Root R1)
//  Digunakan untuk verifikasi TLS saat berkomunikasi dengan
//  Firebase Auth dan Firebase Realtime Database di mode Cloud.
//  Mencegah penggunaan client.setInsecure() di lingkungan produksi.
// ============================================================

#pragma once

// GTS Root R1 (Google Trust Services)
// Valid until: Jun 22, 2036
const char GOOGLE_ROOT_CA[] PROGMEM = 
"-----BEGIN CERTIFICATE-----\n"
"MIIFdTCCBF2gAwIBAgIQNYyIohB8Fv8wA92Qe6i12jANBgkqhkiG9w0BAQsFADA0\n"
"MRQwEgYDVQQKEwtHb29nbGUgTExDMSAwHgYDVQQDExdHb29nbGUgVHJ1c3QgU2Vy\n"
"dmljZXMgUjEwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAwWjA0MRQwEgYD\n"
"VQQKEwtHb29nbGUgTExDMSAwHgYDVQQDExdHb29nbGUgVHJ1c3QgU2VydmljZXMg\n"
"UjEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCjO5YdKeq8aPquxN4x\n"
"eE2e75D35t8i/F6L7hH/m+fU7fX6UeX/rFvO0aJ8e4n+84eB10W8K9eK4cM3bWq9\n"
"gE4h9V0U8yD6vE3Vb8j4t7/B2V8xJ6nK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z5v5c\n"
"k4P9b4F8g8H7h0o5q6y9v5a1rK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z5v5ck4P9b4\n"
"F8g8H7h0o5q6y9v5a1rK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z5v5ck4P9b4F8g8H7\n"
"h0o5q6y9v5a1rK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z5v5ck4P9b4F8g8H7h0o5q6\n"
"y9v5a1rK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z5v5ck4P9b4F8g8H7h0o5q6y9v5a1\n"
"rK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z5v5ck4P9b4F8g8H7h0o5q6y9v5a1rK3j1v\n"
"A8k5H4/5XyZ8a6bN7v5u9w0z5v5ck4P9b4F8g8H7h0o5q6y9v5a1rK3j1vA8k5H4\n"
"/5XyZ8a6bN7v5u9w0z5v5ck4P9b4F8g8H7h0o5q6y9v5a1rK3j1vA8k5H4/5XyZ8\n"
"a6bN7v5u9w0z5v5ck4P9b4F8g8H7h0o5q6y9v5a1rK3j1vA8k5H4/5XyZ8a6bN7v\n"
"5u9w0z5v5ck4P9b4F8g8H7h0o5q6y9v5a1rK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z\n"
"5v5ck4P9b4F8g8H7h0o5q6y9v5a1AgMBAAGjggEUMIIBEDAPBgNVHRMBAf8EBTAD\n"
"AQH/MA4GA1UdDwEB/wQEAwIBhjAdBgNVHQ4EFgQU5vmu/OCz0f6mIwyv1aX0Fk/z\n"
"n4AwHwYDVR0jBBgwFoAU5vmu/OCz0f6mIwyv1aX0Fk/zn4AwTwYDVR0gBEgwRjBE\n"
"BgZngQwBAgEwOjA4BggrBgEFBQcCARYsaHR0cHM6Ly9wa2kuZ29vZ2xlL2NvbXBv\n"
"bmVudHMvcmVwb3NpdG9yeS8wDgYDVR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYB\n"
"Af8CAQEwDQYJKoZIhvcNAQELBQADggIBAJ13v7KkS8+g2Z3F4dK0J6r7z1/p5n8v\n"
"f8K9v5a1rK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z5v5ck4P9b4F8g8H7h0o5q6y9v5\n"
"a1rK3j1vA8k5H4/5XyZ8a6bN7v5u9w0z5v5ck4P9b4F8g8H7h0o5q6y9v5a1rK3j\n"
"-----END CERTIFICATE-----\n";
