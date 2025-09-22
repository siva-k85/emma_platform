/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCvFpqFcROVqhMYIyb9MldKsuTxUe2UI_I',
  authDomain: 'emma---version-1-reboot.firebaseapp.com',
  projectId: 'emma---version-1-reboot',
  storageBucket: 'emma---version-1-reboot.firebasestorage.app',
  messagingSenderId: '365227575795',
  appId: '1:365227575795:web:c6fa4ff6bc190fbdf96a86',
  measurementId: 'G-M1NH8LJSX2',
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  const notificationTitle = payload?.notification?.title || 'EMMA';
  const notificationOptions = {
    body: payload?.notification?.body,
    icon: '/icons/Icon-192.png',
  };
  self.registration.showNotification(notificationTitle, notificationOptions);
});

