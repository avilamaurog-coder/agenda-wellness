{{flutter_js}}
{{flutter_build_config}}

// Agenda Wellness: la app se dibuja dentro de #gc-app (index.html), que ocupa la pantalla menos
// la franja inferior con el crédito de Grupo Capybara y los accesos (productos, regalos, calendario),
// así el menú queda por encima del cartel "Powered by Netlify".
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({ hostElement: document.getElementById("gc-app") });
    await appRunner.runApp();
  },
});
