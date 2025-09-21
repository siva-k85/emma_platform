#!/usr/bin/env node
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import process from 'node:process';
import readline from 'node:readline';
import { createRequire } from 'node:module';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(import.meta.url);

const admin = require('../functions/node_modules/firebase-admin');

function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = { dryRun: false, batchSize: 400, force: false };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    switch (arg) {
      case '--project':
      case '-p':
        parsed.projectId = args[++i];
        break;
      case '--batch-size':
        parsed.batchSize = parseInt(args[++i], 10) || 400;
        break;
      case '--dry-run':
        parsed.dryRun = true;
        break;
      case '--force':
        parsed.force = true;
        break;
      default:
        if (!arg.startsWith('-') && !parsed.projectId) {
          parsed.projectId = arg;
        }
    }
  }
  return parsed;
}

async function confirmOrExit(message) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => rl.question(`${message} (y/N): `, resolve));
  rl.close();
  if (!/^y(es)?$/i.test(answer.trim())) {
    console.log('Aborted.');
    process.exit(0);
  }
}

function normalizeTimestamp(value) {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) return value;
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return admin.firestore.Timestamp.fromDate(date);
}

function ensureEvalBlock(prefix, source, updates, now) {
  const statusNode = source?.status || {};
  const statusValue = statusNode?.status ?? source?.status ?? 'evaluate';
  const lastUpdated = statusNode?.last_updated || statusNode?.lastUpdated;
  const scores = source?.scores;
  const feedback = source?.feedback ?? source?.comments;
  const completed = source?.completed_at ?? source?.completedAt;

  if (statusNode?.status == null && source?.status?.status == null) {
    updates[`${prefix}.status.status`] = statusValue || 'evaluate';
  }
  if (lastUpdated == null) {
    updates[`${prefix}.status.last_updated`] = now;
  }
  if (scores == null) {
    updates[`${prefix}.scores`] = {};
  }
  if (feedback == null) {
    updates[`${prefix}.feedback`] = '';
  }
  if (completed === undefined) {
    updates[`${prefix}.completed_at`] = null;
  }
}

async function main() {
  const { projectId: argProjectId, dryRun, batchSize, force } = parseArgs();
  const projectId = argProjectId || process.env.PROJECT_ID || admin.app()?.options?.projectId;
  if (!projectId) {
    console.error('No project ID supplied. Use --project or set PROJECT_ID.');
    process.exit(1);
  }

  if (!dryRun && !force) {
    await confirmOrExit(`Backfill schedules in project ${projectId}`);
  }

  try {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId
    });
  } catch (err) {
    console.error('Failed to initialize firebase-admin. Ensure ADC credentials are available.');
    console.error(err.message);
    process.exit(1);
  }

  const db = admin.firestore();
  const fieldValue = admin.firestore.FieldValue;
  const schedulesRef = db.collection('schedules');

  let lastDoc = null;
  let scanned = 0;
  let updated = 0;

  let batch = db.batch();
  let batchCount = 0;

  const commitBatch = async () => {
    if (!batchCount) return;
    if (!dryRun) {
      await batch.commit();
    }
    batch = db.batch();
    batchCount = 0;
  };

  while (true) {
    let query = schedulesRef.orderBy(admin.firestore.FieldPath.documentId()).limit(batchSize);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      scanned += 1;
      const data = doc.data();
      const updates = {};
      const now = fieldValue.serverTimestamp();

      if (data.scheduledDate !== undefined) {
        const converted = normalizeTimestamp(data.scheduledDate);
        if (converted && data.scheduled_date === undefined) {
          updates.scheduled_date = converted;
        }
        updates.scheduledDate = fieldValue.delete();
      }

      if (data.shiftTimings !== undefined) {
        const timings = data.shiftTimings || {};
        if (data.shift_timings === undefined) {
          updates['shift_timings'] = {
            start_time: normalizeTimestamp(timings.start_time || timings.startTime),
            end_time: normalizeTimestamp(timings.end_time || timings.endTime),
            duration_minutes: timings.duration_minutes || timings.durationMinutes || null
          };
        }
        updates.shiftTimings = fieldValue.delete();
      }

      if (data.startNotificationSentToAttendee !== undefined) {
        if (data.startNotificationSentToPhysician === undefined) {
          updates.startNotificationSentToPhysician = !!data.startNotificationSentToAttendee;
        }
        updates.startNotificationSentToAttendee = fieldValue.delete();
      }
      if (data.endNotificationSentToAttendee !== undefined) {
        if (data.endNotificationSentToPhysician === undefined) {
          updates.endNotificationSentToPhysician = !!data.endNotificationSentToAttendee;
        }
        updates.endNotificationSentToAttendee = fieldValue.delete();
      }
      if (data.endNotificationFollowupSentToAttendee !== undefined) {
        if (data.endNotificationFollowupSentToPhysician === undefined) {
          updates.endNotificationFollowupSentToPhysician = !!data.endNotificationFollowupSentToAttendee;
        }
        updates.endNotificationFollowupSentToAttendee = fieldValue.delete();
      }

      if (data.residentEvaluationCompleted !== undefined) {
        if (data.resident_evaluation_completed === undefined) {
          updates.resident_evaluation_completed = !!data.residentEvaluationCompleted;
        }
        updates.residentEvaluationCompleted = fieldValue.delete();
      }
      if (data.attendingEvaluationCompleted !== undefined) {
        if (data.attending_evaluation_completed === undefined) {
          updates.attending_evaluation_completed = !!data.attendingEvaluationCompleted;
        }
        updates.attendingEvaluationCompleted = fieldValue.delete();
      }

      const evalSource = data.evaluation_data || data.evaluationData;
      const attendeeEval = evalSource?.attendee_evaluation || evalSource?.attendeeEvaluation || {};
      const residentEval = evalSource?.resident_evaluation || evalSource?.residentEvaluation || {};
      ensureEvalBlock('evaluation_data.attendee_evaluation', attendeeEval, updates, now);
      ensureEvalBlock('evaluation_data.resident_evaluation', residentEval, updates, now);

      if (data.evaluationData !== undefined) {
        updates.evaluationData = fieldValue.delete();
      }

      if (data.schema_version === undefined) {
        updates.schema_version = 1;
      }

      if (Object.keys(updates).length === 0) {
        continue;
      }

      updates.updated_at = now;
      updated += 1;

      if (dryRun) {
        console.log(`Would update schedules/${doc.id}`, updates);
      } else {
        batch.update(doc.ref, updates);
        batchCount += 1;
        if (batchCount >= 400) {
          await commitBatch();
        }
      }
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }

  await commitBatch();
  console.log(`Scanned ${scanned} schedule documents.`);
  console.log(dryRun ? `Would update ${updated} documents.` : `Updated ${updated} documents.`);
  await admin.app().delete();
}

main().catch((err) => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
