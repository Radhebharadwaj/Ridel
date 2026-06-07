importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js");

const firebaseConfig = {
  apiKey: "AIzaSyCylXea35MHpJ4SlcODDAgB5wj6h5SgnzY",
  authDomain: "pixra-ridel.firebaseapp.com",
  projectId: "pixra-ridel",
  storageBucket: "pixra-ridel.firebasestorage.app",
  messagingSenderId: "20390923828",
  appId: "1:20390923828:web:8206196e9cfd1b16790461",
  measurementId: "G-NK274DS7S2",
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  
  // Extract title and body from notification object or data payload
  const notificationTitle = payload.notification?.title || payload.data?.title || 'New Alert';
  
  const notificationOptions = {
    body: payload.notification?.body || payload.data?.body || 'You have a new message',
    // 🎨 Use our new transparent silhouette icon
    icon: '/icons/notify.png',
    // Badge is used on Android devices representing the small monochrome icon
    badge: '/icons/notify.png',
    // 🎨 Primary brand color
    color: '#00E5FF',
    data: payload.data
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
