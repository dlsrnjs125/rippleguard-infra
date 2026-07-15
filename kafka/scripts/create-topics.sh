#!/usr/bin/env sh
set -eu

: "${KAFKA_BOOTSTRAP_SERVER:=kafka:9092}"
: "${KAFKA_TOPIC_PARTITIONS:=3}"
: "${KAFKA_TOPIC_REPLICATION_FACTOR:=1}"
: "${KAFKA_TOPICS_FILE:=/topics/phase1-events.txt}"

: "${KAFKA_TOPICS_BIN:=/opt/kafka/bin/kafka-topics.sh}"

while IFS= read -r topic || [ -n "$topic" ]; do
  case "$topic" in
    ""|\#*) continue ;;
  esac

  "$KAFKA_TOPICS_BIN" \
    --bootstrap-server "$KAFKA_BOOTSTRAP_SERVER" \
    --create \
    --if-not-exists \
    --topic "$topic" \
    --partitions "$KAFKA_TOPIC_PARTITIONS" \
    --replication-factor "$KAFKA_TOPIC_REPLICATION_FACTOR"
done < "$KAFKA_TOPICS_FILE"
