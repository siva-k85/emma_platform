const admin = require("firebase-admin");

// Initialize if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function manualShiftMatching(targetDate = null) {
  console.log("Starting manual shift matching algorithm...");

  try {
    // Use provided date or tomorrow by default
    const matchDate = targetDate ? new Date(targetDate) : new Date();
    if (!targetDate) {
      matchDate.setDate(matchDate.getDate() + 1); // Tomorrow by default
    }
    matchDate.setHours(0, 0, 0, 0); // Start of day

    const dayAfter = new Date(matchDate);
    dayAfter.setDate(dayAfter.getDate() + 1); // End of day

    console.log(`Matching for date: ${matchDate.toISOString().split("T")[0]}`);

    // Step 1: Get all active users categorized by role
    const usersSnapshot = await db
      .collection("users")
      .where("is_active", "==", true)
      .get();

    const residents = [];
    const attendees = [];

    usersSnapshot.forEach((doc) => {
      const user = { id: doc.id, ...doc.data() };
      const role = (user.role || "").toLowerCase();

      // Check for resident roles (resident, Resident)
      if (role === "resident") {
        residents.push(user);
      }
      // Check for attending physician roles (physician, faculty, attending, attendee)
      else if (
        ["physician", "faculty", "attending", "attendee"].includes(role)
      ) {
        attendees.push(user);
      }
    });

    console.log(
      `Found ${residents.length} residents and ${attendees.length} attendees`,
    );

    // Step 2: Check existing schedules to avoid conflicts
    const existingSchedulesSnapshot = await db
      .collection("schedules")
      .where("scheduled_date", ">=", admin.firestore.Timestamp.fromDate(matchDate))
      .where("scheduled_date", "<", admin.firestore.Timestamp.fromDate(dayAfter))
      .get();

    const scheduledResidents = new Set();
    const scheduledAttendees = new Set();

    existingSchedulesSnapshot.forEach((doc) => {
      const schedule = doc.data();
      if (schedule.resident) {
        scheduledResidents.add(schedule.resident.path);
      }
      if (schedule.attendee) {
        scheduledAttendees.add(schedule.attendee.path);
      }
    });

    console.log(
      `Found ${scheduledResidents.size} already scheduled residents and ${scheduledAttendees.size} already scheduled attendees`,
    );

    // Step 3: Get available topics for assignment
    const topicsSnapshot = await db.collection("topics").get();
    const availableTopics = [];

    topicsSnapshot.forEach((doc) => {
      const topic = { id: doc.id, ...doc.data() };
      // Only include non-category topics that have actual content
      if (!topic.topic_data?.is_category && topic.topic_data?.title) {
        availableTopics.push(topic);
      }
    });

    console.log(`Found ${availableTopics.length} available topics`);

    // Step 4: Filter available residents and attendees
    const availableResidents = residents.filter(
      (resident) => !scheduledResidents.has(`users/${resident.id}`),
    );

    const availableAttendees = attendees.filter(
      (attendee) => !scheduledAttendees.has(`users/${attendee.id}`),
    );

    console.log(
      `${availableResidents.length} residents and ${availableAttendees.length} attendees available for scheduling`,
    );

    // Step 5: Generate matching scores and create schedules
    const newSchedules = [];
    const matchedResidents = new Set();
    const matchedAttendees = new Set();

    // Sort residents by PGY level (junior residents get priority)
    availableResidents.sort((a, b) => {
      const pgyA = parseInt(a.pgy_level?.replace("PGY-", "") || "99");
      const pgyB = parseInt(b.pgy_level?.replace("PGY-", "") || "99");
      return pgyA - pgyB;
    });

    for (const resident of availableResidents) {
      if (matchedResidents.has(resident.id)) continue;

      // Find best attendee match for this resident
      let bestAttendee = null;
      let bestScore = -1;

      for (const attendee of availableAttendees) {
        if (matchedAttendees.has(attendee.id)) continue;

        const score = calculateMatchingScore(resident, attendee);
        if (score > bestScore) {
          bestScore = score;
          bestAttendee = attendee;
        }
      }

      if (bestAttendee && availableTopics.length > 0) {
        // Select topic based on resident's level and department
        const selectedTopic = selectTopicForResident(
          resident,
          availableTopics,
        );

        // Generate time slots for the day (9 AM to 5 PM, 1-hour sessions)
        const timeSlots = generateTimeSlots(matchDate);
        const selectedTimeSlot =
          timeSlots[Math.floor(Math.random() * timeSlots.length)];

        const newSchedule = {
          // User references
          attendee: db.doc(`users/${bestAttendee.id}`),
          resident: db.doc(`users/${resident.id}`),
          attendeeRef: `/users/${bestAttendee.id}`,
          residentId: resident.id,
          attendingId: bestAttendee.id,
          facultyId: bestAttendee.id,

          // Scheduling data
          scheduled_date: admin.firestore.Timestamp.fromDate(matchDate),
          date: matchDate.toISOString().split("T")[0],
          time: `${selectedTimeSlot.start.getHours().toString().padStart(2, "0")}:00`,
          start_time: admin.firestore.Timestamp.fromDate(selectedTimeSlot.start),
          end_time: admin.firestore.Timestamp.fromDate(selectedTimeSlot.end),
          shift_timings: {
            start_time: admin.firestore.Timestamp.fromDate(selectedTimeSlot.start),
            end_time: admin.firestore.Timestamp.fromDate(selectedTimeSlot.end),
          },

          // Topic assignment
          assigned_topic: {
            topic_title: selectedTopic.topic_data?.title || "General Medical Topic",
            category_name: selectedTopic.topic_data?.category || "General",
            is_category: false,
            topic_Ref: db.doc(`topics/${selectedTopic.id}`),
            topic_ref: db.doc(`topics/${selectedTopic.id}`),
            topic_id: selectedTopic.id,
          },
          topicId: selectedTopic.id,

          // Fresh evaluation data (ready for evaluation)
          evaluation_data: {
            attendee_evaluation: {
              score: 0,
              attendee_performance_comments: "",
              attendee_suggestions: "",
              is_verbal_feedback_given: false,
              status: {
                status: "evaluate",
                comments: "",
              },
              evaluation_time_logs: {},
            },
            resident_evaluation: {
              score: 0,
              interesting_cases: "",
              is_verbal_feedback_taken: false,
              is_feedback_utilized: false,
              status: {
                status: "evaluate",
                comments: "",
              },
              evaluation_time_logs: {},
            },
          },

          // Evaluation flags
          evaluatedByAttendee: false,
          evaluatedByResident: false,
          evaluationCompleted: false,
          evaluation_status: "pending",

          // Notification flags
          startNotificationSentToAttendee: false,
          startNotificationSentToPhysician: false,
          startNotificationSentToResident: false,
          notification_flags: {
            startNotificationSent: false,
            endNotificationSent: false,
          },

          // Metadata
          schedule_id: `${matchDate.getFullYear()}${(matchDate.getMonth() + 1).toString().padStart(2, "0")}${matchDate.getDate().toString().padStart(2, "0")}_${resident.id}_${bestAttendee.id}`,
          test: false,
          schemaVersion: 2,
          migration_version: "1.0",
          created_by: "manualShiftMatching",
          matching_score: bestScore,

          // Timestamps
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          time_logs: {
            created_time: admin.firestore.FieldValue.serverTimestamp(),
          },
        };

        newSchedules.push(newSchedule);
        matchedResidents.add(resident.id);
        matchedAttendees.add(bestAttendee.id);

        console.log(
          `Matched ${resident.display_name || resident.id} (${resident.pgy_level}) with ${bestAttendee.display_name || bestAttendee.id} for topic: ${selectedTopic.topic_data?.title} (score: ${bestScore})`,
        );
      }
    }

    // Step 6: Batch write new schedules to Firestore
    if (newSchedules.length > 0) {
      const batch = db.batch();

      newSchedules.forEach((schedule) => {
        const scheduleRef = db.collection("schedules").doc(schedule.schedule_id);
        batch.set(scheduleRef, schedule);
      });

      await batch.commit();
      console.log(
        `Successfully created ${newSchedules.length} new schedule entries`,
      );
    } else {
      console.log(
        "No new schedules created - all residents/attendees already scheduled or no matches found",
      );
    }

    // Step 7: Log summary
    const summary = {
      date: matchDate.toISOString().split("T")[0],
      total_residents: residents.length,
      total_attendees: attendees.length,
      available_residents: availableResidents.length,
      available_attendees: availableAttendees.length,
      new_schedules_created: newSchedules.length,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("schedule_matching_logs").add(summary);

    console.log("Manual shift matching completed successfully");
    return summary;
  } catch (error) {
    console.error("Error in manual shift matching:", error);

    // Log error for debugging
    await db.collection("schedule_matching_logs").add({
      error: error.message,
      stack: error.stack,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      type: "error",
    });

    throw error;
  }
}

// Helper function to calculate matching score between resident and attendee
function calculateMatchingScore(resident, attendee) {
  let score = 0;

  // Department match bonus (highest priority)
  if (resident.department === attendee.department) {
    score += 50;
  } else if (resident.department && attendee.department) {
    // Cross-department learning bonus (smaller)
    score += 10;
  }

  // PGY level considerations
  const residentPGY = parseInt(resident.pgy_level?.replace("PGY-", "") || "0");

  // Junior residents (PGY-1, PGY-2) benefit from experienced attendees
  if (residentPGY <= 2) {
    score += 20;
  }

  // Senior residents (PGY-3+) can handle more complex cases
  if (residentPGY >= 3) {
    score += 15;
  }

  // Random factor to add variety (10% of total score)
  score += Math.random() * 10;

  return Math.round(score * 100) / 100; // Round to 2 decimal places
}

// Helper function to select appropriate topic for resident
function selectTopicForResident(resident, availableTopics) {
  if (availableTopics.length === 0) return null;

  const residentPGY = parseInt(resident.pgy_level?.replace("PGY-", "") || "1");
  const department = resident.department?.toLowerCase() || "";

  // Filter topics by complexity level and department relevance
  let suitableTopics = availableTopics.filter((topic) => {
    const title = topic.topic_data?.title?.toLowerCase() || "";
    const description = topic.topic_data?.description?.toLowerCase() || "";

    // Department-specific topic matching
    if (
      department &&
      (title.includes(department) || description.includes(department))
    ) {
      return true;
    }

    // Basic topics for junior residents
    if (residentPGY <= 2) {
      return (
        title.includes("basic") ||
        title.includes("introduction") ||
        title.includes("fundamentals") ||
        description.includes("beginner")
      );
    }

    // Advanced topics for senior residents
    if (residentPGY >= 3) {
      return (
        title.includes("advanced") ||
        title.includes("complex") ||
        description.includes("advanced") ||
        description.includes("expert")
      );
    }

    return true; // Default: all topics suitable
  });

  // If no suitable topics found, use all available topics
  if (suitableTopics.length === 0) {
    suitableTopics = availableTopics;
  }

  // Select random topic from suitable ones
  return suitableTopics[Math.floor(Math.random() * suitableTopics.length)];
}

// Helper function to generate time slots for a day
function generateTimeSlots(date) {
  const slots = [];
  const workdayStart = new Date(date);
  workdayStart.setHours(9, 0, 0, 0); // 9 AM

  const workdayEnd = new Date(date);
  workdayEnd.setHours(17, 0, 0, 0); // 5 PM

  let currentTime = new Date(workdayStart);

  while (currentTime < workdayEnd) {
    const slotStart = new Date(currentTime);
    const slotEnd = new Date(currentTime);
    slotEnd.setHours(slotEnd.getHours() + 1); // 1-hour sessions

    slots.push({
      start: slotStart,
      end: slotEnd,
    });

    currentTime.setHours(currentTime.getHours() + 1);
  }

  return slots;
}

// Parse command line arguments
const args = process.argv.slice(2);
let targetDate = null;

if (args.length > 0) {
  // Accept date in format: YYYY-MM-DD or "today"
  if (args[0] === "today") {
    targetDate = new Date();
  } else if (args[0].match(/^\d{4}-\d{2}-\d{2}$/)) {
    targetDate = new Date(args[0]);
  } else {
    console.error("Invalid date format. Use YYYY-MM-DD or 'today'");
    process.exit(1);
  }
}

// Run the manual matching
manualShiftMatching(targetDate)
  .then((summary) => {
    console.log("\n✅ MANUAL SHIFT MATCHING COMPLETE!");
    console.log("Summary:", summary);
    process.exit(0);
  })
  .catch((error) => {
    console.error("\n❌ MANUAL SHIFT MATCHING FAILED!");
    console.error(error);
    process.exit(1);
  });