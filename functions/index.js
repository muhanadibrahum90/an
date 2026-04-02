const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onValueCreated } = require("firebase-functions/v2/database");
const { initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");
const { getDatabase } = require("firebase-admin/database");
const { getMessaging } = require("firebase-admin/messaging");
const { onCall } = require("firebase-functions/v2/https");

initializeApp();
const db = getFirestore();

function calcScore(data, nowMs) {
  const ageMin = (nowMs - data.createdAt.toMillis()) / (1000 * 60);
  const ageH   = ageMin / 60;

  const interactions = (data.likeCount    || 0)
                     + (data.commentCount || 0) * 2
                     + (data.shareCount   || 0) * 3;

  // المرحلة الأولى: 0 → 3 ساعات
  if (ageH < 3) {
    let ageBonus = 0;
    if      (ageMin < 15) ageBonus = 400;
    else if (ageMin < 40) ageBonus = 350;
    else if (ageMin < 60) ageBonus = 300;
    else if (ageH   < 2)  ageBonus = 200;
    else                  ageBonus = 150;

    return parseFloat((interactions + ageBonus).toFixed(4));
  }

  // المرحلة الثانية: 3 ساعات فأكثر
  let multiplier = 1.0;
  if      (ageH < 6)  multiplier = 2.0;
  else if (ageH < 12) multiplier = 1.8;
  else if (ageH < 24) multiplier = 1.5;
  else if (ageH < 36) multiplier = 0.5;
  else if (ageH < 48) multiplier = 0.3;
  else                multiplier = 0.1;

  return parseFloat((interactions * multiplier).toFixed(4));
}

exports.updateTrendScores = onSchedule(
  {
    schedule: "every 2 minutes",  
    timeZone: "Asia/Riyadh",
    memory: "512MiB",
  },
  async () => {
    const nowMs  = Date.now();
    const cut7d  = Timestamp.fromMillis(nowMs - 7 * 24 * 60 * 60 * 1000);

    const snap = await db
      .collection("posts")
      .where("createdAt", ">=", cut7d)
      .get();

    let batch = db.batch();
    let count = 0;

    const flush = async () => {
      if (count > 0) await batch.commit();
      batch = db.batch();
      count = 0;
    };

    for (const doc of snap.docs) {
      const data     = doc.data();
      const newScore = calcScore(data, nowMs);
      const oldScore = data.trendScore || 0;

      if (Math.abs(newScore - oldScore) > 0.5) {
        batch.update(doc.ref, { trendScore: newScore });
        if (++count % 499 === 0) await flush();
      }
    }

    await flush();
  },
);

// حذف الإشعارات  
exports.deleteOldNotifications = onSchedule(
  {
    schedule: "0 2 * * *",
    timeZone: "Asia/Riyadh",
    memory: "256MiB",
  },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);

    const expiredNotifs = await db
      .collectionGroup("items")
      .where("createdAt", "<", cutoff)
      .limit(1000) 
      .get();

    if (expiredNotifs.empty) return;

    let batch = db.batch();
    let count = 0;

    for (const doc of expiredNotifs.docs) {
      batch.delete(doc.ref);
      count++;
      if (count === 500) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }

    if (count > 0) await batch.commit();
  },
);

// إشعار Firestore

exports.onNotificationCreated = onDocumentCreated(
  {
    document: "notifications/{uid}/items/{notifId}",
    region: "us-central1",
    firestoreLocation: "us-central1",
  },
  async (event) => {
    const uid = event.params.uid;
    const notif = event.data?.data();
    if (!notif) return;

    const userDoc = await db.collection("users").doc(uid).get();
    const token = userDoc.data()?.fcmToken;
    if (!token) return;

    let title = "",
      body = "";

    switch (notif.type) {
      case "follow":
        title = "لديك متابع جديد";
        body = `${notif.fromUsername} بدأ في متابعتك`;
        break;

      case "like_milestone":
        title = "إعجابات على منشورك";
        body = `حصل منشورك على ${notif.count} إعجاب`;
        break;

      case "comment":
        title = "تعليق على منشورك";
        body = `${notif.fromUsername} أضاف رداً على منشورك`;
        break;

      default:
        return;
    }

    try {
      await getMessaging().send({
        token,
        notification: { title, body },
        data: {
          type: notif.type,
          postId: notif.postId ?? "",
          uid: notif.fromUid ?? "",
        },
        android: { notification: { channelId: "default", priority: "high" } },
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
      });
    } catch (error) {
      if (
        error.code === "messaging/registration-token-not-registered" ||
        error.code === "messaging/invalid-argument"
      ) {
        await db
          .collection("users")
          .doc(uid)
          .update({ fcmToken: FieldValue.delete() });
      }
    }
  },
);

exports.deleteUserData = onCall({ region: "us-central1" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new Error("Unauthorized");

  async function deleteCollection(ref) {
    const snap = await ref.limit(100).get();
    if (snap.empty) return;
    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    if (snap.size === 100) await deleteCollection(ref);
  }

  // 1. منشورات
  const postsSnap = await db.collection("posts").where("uid", "==", uid).get();
  for (const post of postsSnap.docs) {
    await deleteCollection(post.ref.collection("likes"));
    await deleteCollection(post.ref.collection("comments"));
    await deleteCollection(post.ref.collection("reports"));
    await post.ref.delete();
  }

  // 2. المتابعين
  const followersSnap = await db
    .collection("users")
    .doc(uid)
    .collection("followers")
    .get();
  if (!followersSnap.empty) {
    const batch = db.batch();
    for (const doc of followersSnap.docs) {
      batch.delete(
        db.collection("users").doc(doc.id).collection("following").doc(uid),
      );
      batch.update(db.collection("users").doc(doc.id), {
        followingCount: FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }

  const followingSnap = await db
    .collection("users")
    .doc(uid)
    .collection("following")
    .get();
  if (!followingSnap.empty) {
    const batch = db.batch();
    for (const doc of followingSnap.docs) {
      batch.delete(
        db.collection("users").doc(doc.id).collection("followers").doc(uid),
      );
      batch.update(db.collection("users").doc(doc.id), {
        followersCount: FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }

  // 3. subcollections
  await deleteCollection(
    db.collection("users").doc(uid).collection("followers"),
  );
  await deleteCollection(
    db.collection("users").doc(uid).collection("following"),
  );

  // 4. الإشعارات
  await deleteCollection(
    db.collection("notifications").doc(uid).collection("items"),
  );
  await db.collection("notifications").doc(uid).delete();

  // 5. username
  const userDoc = await db.collection("users").doc(uid).get();
  const username = userDoc.data()?.username;
  if (username) await db.collection("usernames").doc(username).delete();

  // 6. مستند المستخدم
  await db.collection("users").doc(uid).delete();

  return { success: true };
});

// إشعار Realtime DB

exports.onNewChatMessage = onValueCreated(
  {
    ref: "chats/{chatId}/messages/{messageId}",
    region: "us-central1",
    instance: "aan-app-71294-default-rtdb",
  },
  async (event) => {
    const message = event.data.val();
    if (!message) return;

    const chatId = event.params.chatId;
    const senderId = message.senderId;

    const infoSnap = await getDatabase().ref(`chats/${chatId}/info`).get();
    const info = infoSnap.val();
    if (!info) return;

    const participantsSnap = await getDatabase()
      .ref(`chats/${chatId}/participants`)
      .get();
    const participants = participantsSnap.val() ?? {};

    const receiverId = Object.keys(participants).find(
      (uid) => uid !== senderId,
    );
    if (!receiverId) return;

    const receiverDoc = await db.collection("users").doc(receiverId).get();
    const token = receiverDoc.data()?.fcmToken;
    if (!token) return;

    const senderName =
      (info.usersInfo ?? {})[senderId]?.displayName ?? "مستخدم";
    const body = message.type === "image" ? "أرسل صورة" : (message.text ?? "");

    try {
      await getMessaging().send({
        token,
        notification: { title: senderName, body },
        data: { type: "message", chatId: chatId, uid: senderId },
        android: { notification: { channelId: "messages", priority: "high" } },
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
      });
    } catch (error) {
      if (error.code === "messaging/registration-token-not-registered") {
        await db
          .collection("users")
          .doc(receiverId)
          .update({ fcmToken: FieldValue.delete() });
      }
    }
  },
);


exports.checkReportedPosts = onSchedule(
  {
    schedule: "every 12 hours", 
    timeZone: "Asia/Riyadh",
    memory: "256MiB",
  },
  async () => {
    const REPORT_THRESHOLD = 80;

    const snap = await db
      .collection("posts")
      .where("reportCount", ">=", REPORT_THRESHOLD)
      .get();

    if (snap.empty) {
      return;
    }

    for (const doc of snap.docs) {
      const postId = doc.id;
      const postData = doc.data();
      const ownerId = postData.uid;

      async function deleteSubcollection(colRef) {
        const s = await colRef.limit(100).get();
        if (s.empty) return;
        const batch = db.batch();
        s.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        if (s.size === 100) await deleteSubcollection(colRef);
      }

      const postRef = db.collection("posts").doc(postId);
      await deleteSubcollection(postRef.collection("likes"));
      await deleteSubcollection(postRef.collection("comments"));
      await deleteSubcollection(postRef.collection("reports"));

      // ─── احذف المنشور ───
      await postRef.delete();

      await db
        .collection("notifications")
        .doc(ownerId)
        .collection("items")
        .add({
          type: "post_deleted_by_reports",
          createdAt: FieldValue.serverTimestamp(),
          isRead: false,
        });

      //  أرسل إشعار واحد فقط لصاحب المنشور 
      const ownerDoc = await db.collection("users").doc(ownerId).get();
      const token = ownerDoc.data()?.fcmToken;

      if (token) {
        try {
          await getMessaging().send({
            token,
            notification: {
              title: "تم حذف منشورك",
              body: "تم حذف منشورك بسبب البلاغات التي تلقيناها",
            },
            data: {
              type: "post_deleted_by_reports",
              postId: postId,
            },
            android: {
              notification: { channelId: "default", priority: "high" },
            },
            apns: { payload: { aps: { sound: "default", badge: 1 } } },
          });
        } catch (error) {
          if (
            error.code === "messaging/registration-token-not-registered" ||
            error.code === "messaging/invalid-argument"
          ) {
            await db.collection("users").doc(ownerId).update({
              fcmToken: FieldValue.delete(),
            });
          }
        }
      }
    }
  },
);

exports.deleteBannedUsers = onSchedule(
  {
    schedule: "40 14 * * *",
    timeZone: "Asia/Riyadh",
    memory: "512MiB",
  },
  async () => {
    const snap = await db
      .collection("users")
      .where("isBanned", "==", true)
      .where("bannedScreenSeen", "==", true)
      .get();

    if (snap.empty) {
      return;
    }

    for (const userDoc of snap.docs) {
      const uid = userDoc.id;

      const postsSnap = await db
        .collection("posts")
        .where("uid", "==", uid)
        .get();
      const postIds = postsSnap.docs
        .map((d) => d.data().postId ?? "")
        .filter((id) => id !== "");

      try {
        await fetch(
          "https://aan-upload.aan52907394.workers.dev/delete-account",
          {
            method: "POST",
            headers: {
              "X-Admin-Secret": "An_mmee_app_3zv1", 
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ uid, postIds }),
          },
        );
      } catch (e) {
      }

      try {
        // 1. حذف منشوراته
        const postsSnap = await db
          .collection("posts")
          .where("uid", "==", uid)
          .get();
        for (const post of postsSnap.docs) {
          await _deleteSubcollection(post.ref.collection("likes"));
          await _deleteSubcollection(post.ref.collection("comments"));
          await _deleteSubcollection(post.ref.collection("reports"));
          await post.ref.delete();
        }

        // 2. تحديث المتابعين
        const followersSnap = await db
          .collection("users")
          .doc(uid)
          .collection("followers")
          .get();
        if (!followersSnap.empty) {
          const batch = db.batch();
          for (const doc of followersSnap.docs) {
            batch.delete(
              db
                .collection("users")
                .doc(doc.id)
                .collection("following")
                .doc(uid),
            );
            batch.update(db.collection("users").doc(doc.id), {
              followingCount: FieldValue.increment(-1),
            });
          }
          await batch.commit();
        }

        const followingSnap = await db
          .collection("users")
          .doc(uid)
          .collection("following")
          .get();
        if (!followingSnap.empty) {
          const batch = db.batch();
          for (const doc of followingSnap.docs) {
            batch.delete(
              db
                .collection("users")
                .doc(doc.id)
                .collection("followers")
                .doc(uid),
            );
            batch.update(db.collection("users").doc(doc.id), {
              followersCount: FieldValue.increment(-1),
            });
          }
          await batch.commit();
        }

        // 3. حذف subcollections
        await _deleteSubcollection(
          db.collection("users").doc(uid).collection("followers"),
        );
        await _deleteSubcollection(
          db.collection("users").doc(uid).collection("following"),
        );
        await _deleteSubcollection(
          db.collection("notifications").doc(uid).collection("items"),
        );
        await db.collection("notifications").doc(uid).delete();

        // 4. حذف username
        const userData = userDoc.data();
        if (userData.username) {
          await db.collection("usernames").doc(userData.username).delete();
        }

        // 5. حذف مستند المستخدم
        await db.collection("users").doc(uid).delete();

        // 6. حذف من Firebase Auth
        await getAuth().deleteUser(uid);

      } catch (e) {
      }
    }

  },
);

async function _deleteSubcollection(colRef) {
  const snap = await colRef.limit(100).get();
  if (snap.empty) return;
  const batch = db.batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  if (snap.size === 100) await _deleteSubcollection(colRef);
}
