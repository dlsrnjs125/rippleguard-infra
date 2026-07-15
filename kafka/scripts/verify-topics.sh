#!/usr/bin/env sh
set -eu

: "${KAFKA_BOOTSTRAP_SERVER:=kafka:9092}"
: "${KAFKA_TOPICS_FILE:=/topics/phase1-events.txt}"

: "${KAFKA_TOPICS_BIN:=/opt/kafka/bin/kafka-topics.sh}"
actual_topics="$("$KAFKA_TOPICS_BIN" --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" --list)"

while IFS= read -r topic || [ -n "$topic" ]; do
  case "$topic" in
    ""|\#*) continue ;;
  esac

  if ! printf '%s\n' "$actual_topics" | grep -Fx "$topic" >/dev/null; then
    echo "Missing Kafka topic: $topic" >&2
    exit 1
  fi
done < "$KAFKA_TOPICS_FILE"

echo "Kafka topics verified"
