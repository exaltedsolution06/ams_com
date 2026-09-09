# Apache Tika (pulled in transitively, likely via file_picker / mobile_scanner)
# references desktop-only javax.xml.stream (StAX) classes that don't exist on
# Android. These code paths aren't exercised at runtime in this app, so tell
# R8 not to fail the build over them.
-dontwarn org.apache.tika.**
-dontwarn javax.xml.stream.**
-dontwarn javax.xml.**
