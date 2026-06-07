# 🚀 Ridel Global Broadcast Guide (Zero-UI Method)

This guide explains how to send push notifications to ALL Ridel users instantly using our Cloudflare Worker API. We use the "Zero-UI" method to keep the main app secure and lightweight.

## 🛠️ Step 1: Prerequisites
1. Open your code editor (VS Code / Cursor / Windsurf).
2. Go to Extensions (`Ctrl+Shift+X` or `Cmd+Shift+X`).
3. Search for and install **Thunder Client** (It's like Postman but built inside VS Code).
4. Click on the Thunder Client icon in your left sidebar and click **"New Request"**.

---

## 📡 Step 2: The API Request Setup

Set up your Thunder Client request exactly like this:

* **Method:** `POST`
* **URL:** `https://ridel.ridel.workers.dev/admin/broadcast`

---

## 🔐 Step 3: Headers (Security)
Go to the **Headers** tab in Thunder Client and add our secret key to prove you are the Admin.

| Key | Value |
| :--- | :--- |
| `Admin-Secret` | *(Paste your APP_SECRET_PASSKEY from .env here)* |
| `Content-Type` | `application/json` |

---

## 📝 Step 4: JSON Payload (The Message)
Go to the **Body** tab, select **JSON**, and paste one of the examples below depending on what you want to send.

### Example 1: Simple Info Alert
Use this for general announcements.

```json
{
  "title": "Delhi Metro Update 🚇",
  "body": "Aqua Line is experiencing a 15-minute delay. Please plan accordingly."
}

Example 2: Update with Deep Link
Use this if you want the user to click the notification and open a specific page in the app (e.g., the map or a specific route).

JSON
{
  "title": "New DTC Routes Added! 🚌",
  "body": "We have just added 50+ new DTC bus routes. Tap to view them on the live map.",
  "deepLink": "/map?layer=bus"
}
Example 3: Maintenance Alert
JSON
{
  "title": "Scheduled Maintenance 🛠️",
  "body": "Ridel servers will be upgrading tonight at 2:00 AM for 15 minutes."
}

🚀 Step 5: Fire It!
Click the SEND button.

If successful, you will get a 200 OK response with the Firebase Message ID.

The message will instantly hit the lock screens of all users subscribed to the all_users topic.

⚠️ WARNING: This is a live production endpoint. Any message sent from here goes to EVERY single user who has the app installed. Double-check your spelling before hitting Send!