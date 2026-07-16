# Revocación de dispositivo y estado Cloud/LAN

## Objetivo

Hacer explícita la diferencia entre una sesión de JUJO.Cloud y el pairing TLS
local, y ofrecer una acción segura para revocar este dispositivo del servidor.

## Principios

- La sesión Cloud y el certificado TLS local son credenciales distintas.
- Cerrar sesión Cloud no revoca automáticamente el pairing local ni otros
  dispositivos. Esto conserva el acceso LAN/offline emparejado.
- Una revocación debe alcanzar al servidor antes de borrar el registro local.
  La interfaz nunca afirmará que se revocó una autorización si el servidor no
  confirmó la operación.
- La acción no cambia el perfil Cloud del servidor ni afecta a otros clientes.

## Estados presentados

Para un servidor emparejado:

| Registro del servidor | Sesión JUJO.Cloud | Texto visible |
| --- | --- | --- |
| Local | No aplica | Emparejado localmente |
| Registrado en Cloud | Activa | Emparejado · JUJO.Cloud conectado |
| Registrado en Cloud y visible por LAN | Inactiva | Emparejado localmente · Cloud desconectado |

Los servidores no emparejados continúan usando el estado actual de pairing.

## Acciones de servidor

Las tres acciones son intencionalmente diferentes:

- **Desemparejar:** elimina el pairing del servidor, pero conserva la tarjeta
  para un nuevo pairing.
- **Eliminar:** elimina solo el registro local; no revoca la autorización ya
  conocida por el servidor.
- **Olvidar y revocar este dispositivo:** revoca el certificado/identidad de
  este cliente en el servidor y, solo tras éxito, elimina el registro local.

## Flujo de revocación

1. La acción se presenta como destructiva, con nombre del servidor y una
   explicación de que requerirá emparejar de nuevo.
2. El usuario confirma; cancelar conserva todo sin cambios.
3. El cliente usa el flujo de unpair autenticado ya existente contra el
   servidor seleccionado.
4. Si el servidor confirma, se elimina el registro local y cualquier
   preferencia visual asociada a esa tarjeta.
5. Si el servidor no responde o rechaza la operación, se conserva el registro
   y se muestra un error accionable para reintentar. Nunca se hace una
   revocación local optimista.

## Alcance y seguridad

- No se elimina la identidad criptográfica global de la aplicación: podría
  romper otros servidores emparejados.
- No se fuerza cierre de sesión Cloud ni se modifica el perfil Cloud del
  servidor.
- No se habilita pairing Cloud ni se relaja la validación TLS.

## Verificación

- Las pruebas cubren los textos de estado para pairing local y sesión Cloud.
- Las pruebas cubren éxito de revocación y fallo de red, comprobando que el
  registro local solo desaparece en el primer caso.
- Análisis de Dart, pruebas focalizadas y build release Android.
