# DBACOCKPIT – Regresión en Windows 11 (sesión del 24.10.2026)

Continuación de [`SAP731_SYBASE_DBACOCKPIT_FIX.md`](https://github.com/dev-lang/sap_time/blob/main/SAP731_SYBASE_DBACOCKPIT_FIX.md). Los fuentes y diffs de las mejoras están en [`enhancements/`](../enhancements/). El error vuelve a aparecer en la PC con Windows 11, que es donde está instalado el sistema BAS. En la PC con Windows 10, con el mismo SAP GUI 770, DBACOCKPIT funciona.

## Síntomas

| Dónde | Qué se ve |
|---|---|
| DBACOCKPIT dentro de SAP GUI (Win11) | Login de SAP NetWeaver con *"You are calling this Web site with a browser that is not supported"* |
| "Start in Web Browser" (navegador externo) | `500 SAP Internal Server Error` – *Access via 'NULL' object reference not possible (RABAX_STATE)*. En los intentos siguientes da 500 de una |
| ST22 | `OBJECTS_OBJREF_NOT_ASSIGNED` en `CL_DBA_RDI=>GET_INSTANCE`, usuario SAPADMIN, mandante 001 (3 dumps el 23.10 entre las 23:26 y las 23:34) |

Son **dos problemas distintos**, uno en cada camino.

---

## Problema 1 – SAP GUI: emulación de IE11 en el registro (causa principal)

### Diagnóstico

En `HKLM\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION` (Win11 24H2, build 26100) **volvieron a aparecer** estas entradas:

| Valor | Dato |
|---|---|
| SAPGUI.exe | `0x2af9` (11001) |
| SAPGUISERVER.exe | `0x2af9` (11001) |
| SAPLGPAD.exe | `0x2af9` (11001) |
| SAPLOGON.exe | `0x2af9` (11001) |

Es exactamente el caso del **Paso 1d** de la guía original: SAP GUI se identifica como IE11 en modo estándar y Web Dynpro 7.31 no lo reconoce. Por eso aparece el login con "browser not supported" en lugar de la aplicación. Lo más probable es que las entradas se hayan recreado al reinstalar o actualizar SAP GUI, algo que la guía ya advertía. En Win10 no están, y por eso ahí funciona.

En la misma clave también hay entradas de otras aplicaciones (HelpPane, prevhost, QfinderPro, Snagit). Esas no se tocan.

### Solución

En una consola **como administrador**:

```bat
reg export "HKLM\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION" C:\backup_browser_emulation_20261024.reg
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION" /v SAPLOGON.exe /f
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION" /v SAPLGPAD.exe /f
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION" /v SAPGUI.exe /f
reg delete "HKLM\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION" /v SAPGUISERVER.exe /f
```

Revisar también la misma clave sin `WOW6432Node` y la de usuario. Si aparecen las mismas cuatro entradas, borrarlas igual:

```bat
reg query "HKLM\SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION"
reg query "HKCU\SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION"
```

Después, cerrar SAP Logon por completo (incluido el ícono de la bandeja) y volver a abrirlo. En **Opciones → Diseño interactivo → Parametrizaciones de control → Control de navegador** tiene que quedar **Internet Explorer**.

### Verificación
`/nDBACOCKPIT` desde SAP GUI tiene que abrir la aplicación sin pedir login, como en el Paso 4 de la guía original.

---

## Problema 2 – "Start in Web Browser": dump en `CL_DBA_RDI=>GET_INSTANCE`

### Diagnóstico (ST22 + código)

Pila de llamadas del dump:

```
16  CL_DBA_RDI=>GET_INSTANCE              (CM002, línea 3)   <- terminación
15  CL_DB6_TREE_NAVIGATOR->SET_TEST_MODE  (CM04D, línea 13)
14  DBA_COCKPIT / vista STARTUP -> HANDLEINTO_STARTUP
    ... CL_WDR_* ... SAPMHTTP (pedido HTTP)
```

Variables: `SYS_REF = {O:initial}`.

Encadenamiento:

1. `STARTUP->HANDLEINTO_STARTUP` (líneas 76–115) busca el sistema a monitorear:
   - Si la URL no trae sistema (`startup_system_id` vacío), lo toma del perfil del usuario: `user_session->get_profile_parameter(...)`. El perfil vive en la personalización `SPERS_OBJ` (clave `DB6NAV`, por usuario).
   - Si no consigue un sistema, `sys_ref = nav_ref->system`, que todavía es NULL. En ese caso no llama a `set_system` y solo cambia la acción a "System Configuration".
2. En la línea 123 llama **siempre** a `nav_ref->set_test_mode( ... )`.
3. `SET_TEST_MODE` hace `cl_dba_rdi=>get_instance( me->system )` con `me->system` en NULL.
4. `GET_INSTANCE`, línea 3: `if rdi is initial or rdi->sys_ref->sys_data-sysid <> sys_ref->sys_data-sysid` desreferencia el `sys_ref` NULL y genera el dump.

En resumen, cuando el cockpit arranca **sin un sistema resuelto**, el código estándar 731 se cae en lugar de mostrar la configuración. Pasa al entrar por el navegador externo, donde la URL no lleva el sistema que sí pasa la transacción de SAP GUI. Que pase o no depende de lo que tenga guardado el usuario en su personalización.

Los "500 de una" de los intentos siguientes no generaron dumps nuevos en ST22 (Today = 0). Ahí el corte es por el chequeo de navegador de Web Dynpro 7.31 (KBA 2976018, `ABORT_MESSAGE_STATE`), no por este dump.

### Solución aplicada (sin nota de SAP)

No hay acceso para descargar notas, así que se resolvió con dos cambios locales.

**2a. Sistema por defecto.** En DBACOCKPIT → System Configuration, seleccionar la fila BAS → botón **Default System**. Aparece el mensaje *"System BAS has been set as default system to start with"* y la estrella en la columna Default. Este valor se guarda **por usuario** (personalización `SPERS_OBJ` / `DB6NAV`), así que hay que repetirlo con cada usuario que entre por navegador.

**2b. Mejora `ZE_DB6_NAV_TESTMODE`** (Overwrite-Method sobre `CL_DB6_TREE_NAVIGATOR→SET_TEST_MODE`). Cubre a cualquier usuario, tenga o no sistema por defecto.

No se usó una opción implícita al principio del método porque en esta versión `SET_TEST_MODE` solo ofrece la del final. Un pre-exit tampoco sirve, porque no puede cortar la ejecución del método original.

Pasos:

1. SE24 → `CL_DB6_TREE_NAVIGATOR` → Display → **Class → Enhance**.
2. Enhancement Implementation `ZE_DB6_NAV_TESTMODE`, texto "DBACOCKPIT: SET_TEST_MODE sin sistema" → **Local Object** ($TMP).
3. Seleccionar `SET_TEST_MODE` → **Edit → Enhancement Operations → Insert Overwrite-Method** → acceso a privados: **Yes**.
4. Clic en el ícono de la columna Overwrite-Exit → guardar → pegar el código de abajo entre el bloque de comentarios y `ENDMETHOD.`
5. Ctrl+F2 (debe dar "syntactically correct") → Ctrl+S → Ctrl+F3, marcando **sólo** `ZE_DB6_NAV_TESTMODE` → "Object(s) activated".

Código: es el original con `me->` reemplazado por `core_object->` y el `IF ... IS NOT BOUND` agregado.

```abap
  DATA: lr_rdi      TYPE REF TO cl_dba_rdi,
        ex_dba_rdi  TYPE REF TO cx_dba_rdi,
        ex_dba_root TYPE REF TO cx_dba_root.

  core_object->test_mode = test_mode.

* Sin sistema seleccionado (arranque web sin sistema por defecto)
* no hay back-end RDI: CL_DBA_RDI=>GET_INSTANCE daria dump
  IF core_object->system IS NOT BOUND.
    RETURN.
  ENDIF.

  IF core_object->test_ref IS NOT BOUND.
    core_object->test_ref = cl_dba_test_handler=>get_instance( ).
    TRY.
        lr_rdi = cl_dba_rdi=>get_instance( core_object->system ).
        lr_rdi->query->set_test_handler( core_object->test_ref ).
      CATCH cx_dba_rdi INTO ex_dba_rdi.                 "#EC NO_HANDLER
        core_object->msgwindow->add_exception_class( ex_dba_rdi ).
    ENDTRY.
  ENDIF.

  IF core_object->test_ref IS BOUND.
    TRY.
        core_object->test_ref->set_test_mode(
          sys_ref   = core_object->system
          time_from = core_object->selection_timeframe->from_date &&
                      core_object->selection_timeframe->from_time
          time_to   = core_object->selection_timeframe->to_date &&
                      core_object->selection_timeframe->to_time
          test_mode = test_mode ).
      CATCH cx_dba_root INTO ex_dba_root.
        core_object->msgwindow->add_exception_class( ex_dba_root ).
    ENDTRY.
  ENDIF.
```

Efecto: si se arranca sin sistema, el cockpit sigue el flujo estándar y abre **System Configuration**, sin dump. El "test mode" sólo se usa en la Test Suite y, cuando hay sistema, funciona igual que antes.

**Deshacer:** SE24 → `CL_DB6_TREE_NAVIGATOR` → Class → Enhance → borrar o desactivar `ZE_DB6_NAV_TESTMODE`. Si se sube un SP de SAP_BASIS, revisarla en SPAU_ENH.

### Notas

- El camino válido en 7.31 sigue siendo DBACOCKPIT dentro de SAP GUI. Desde un navegador moderno, Web Dynpro 7.31 puede seguir mostrando el aviso de navegador no soportado (KBA 2976018), aunque ya no tire dump.
- Limpiar sesiones colgadas en SM05/SM04 después de los intentos fallidos.

---

---

## Problema 3 – "Start in Web Browser" sigue dando 500 (sin dump): chequeo de navegador

Después de aplicar la mejora, el 500 sigue apareciendo pero ya **no genera dump** (ST22: 0 errores hoy). El motivo está en ST11 → `dev_icf0`:

```
<ErrorInfo URL="http://sapzrv.lab.local:8000/sap/bc/webdynpro/sap/dba_cockpit">
<ErrorMessage>This browser is not supported</ErrorMessage>
<User>SAPADMIN</User> <Client>001</Client> <Time>073954</Time>
<TerminationType>ERROR_MESSAGE_STATE</TerminationType>
CL_WDR_CLIENT_ABSTRACT_HTTP->CLIENT_INSPECTOR_CREATE_CLIENT
```

### Diagnóstico (código + debugger)

Cadena del chequeo:

```
CL_WDR_CLIENT_ABSTRACT_HTTP=>CLIENT_INSPECTOR_CREATE_CLIENT
  -> CL_WDR_CLIENT_SSR_LS->IF_WDR_CLIENT~FULFILLS
     -> CLUR_NW7_SERVER=>DETECT_USER_AGENT(_NEW)
        -> CLUR_NW7_USER_AGENT_INFO->SET_USER_AGENT_INFO   (regex por navegador)
        -> CLUR_NW7_USER_AGENT_INFO->SET_LIGHTSPEED_INFO   (reglas "soportado")
  si supported = false -> MESSAGE e015(webdynpro_rt) "This browser is not supported"
```

"Start in Web Browser" abre **Internet Explorer**, que en este Windows 11 todavía funciona. Con un breakpoint externo en `SET_LIGHTSPEED_INFO` se vieron dos user agents:

| Pedido | User agent | Resultado en 7.31 |
|---|---|---|
| 1º | `Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko` (IE11 estándar, 69 caracteres) | Ninguna regex lo reconoce (IE11 ya no manda "MSIE") → todo vacío → **no soportado → 500** |
| 2º | `Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 10.0; WOW64; Trident/7.0; ...)` | Regla "MSIE >= 6.0" → soportado |

Hay además un bug de fondo en las reglas de `SET_LIGHTSPEED_INFO`: `version` es `TYPE string` y se compara como texto (`version ge '8.0'`, `ge '6.0'`). Cualquier versión de 2 o 3 dígitos queda rechazada: Chrome/Edge `'155.0' < '8.0'`, IE `'11.0' < '6.0'`.

### Solución aplicada: mejora `ZE_UR_UA_VERSION100` (sin nota)

Dos **Post-Methods** sobre `CLUR_NW7_USER_AGENT_INFO`, en $TMP:

1. SE24 → `CLUR_NW7_USER_AGENT_INFO` → Class → Enhance → crear `ZE_UR_UA_VERSION100` ("WD: navegadores con version >= 100") → Local Object.
2. Para cada método: seleccionarlo → Edit → Enhancement Operations → **Insert Post-Method** → acceso a privados **Yes** → clic en el ícono de la columna PostExit → pegar el código → Ctrl+F2 → Ctrl+S → Ctrl+F3, marcando sólo `ZE_UR_UA_VERSION100`.

**Post-exit de `SET_USER_AGENT_INFO`:** reconoce IE11.

```abap
  DATA: lv_os TYPE string,
        lv_rv TYPE string.

  CHECK core_object->user_agent_info-browser IS INITIAL.

  FIND FIRST OCCURRENCE OF REGEX
       'Windows NT (\d+\.\d+).*Trident/\d+\.\d+.*rv:(\d+\.\d+)'
       IN user_agent_string SUBMATCHES lv_os lv_rv.
  CHECK sy-subrc = 0.

  core_object->user_agent_info-id            = 'IE on WinNT'.
  core_object->user_agent_info-browser       = 'MSIE'.
  core_object->user_agent_info-version       = lv_rv.
  core_object->user_agent_info-platform      = 'Windows'.
  core_object->user_agent_info-mobile        = abap_false.
  core_object->user_agent_info-osname        = 'Windows NT'.
  core_object->user_agent_info-osversion     = lv_os.
  core_object->user_agent_info-enginename    = 'MSIE'.
  core_object->user_agent_info-engineversion = lv_rv.
```

**Post-exit de `SET_LIGHTSPEED_INFO`:** reevalúa las reglas con la versión mayor como número.

```abap
  DATA: lv_major TYPE string,
        lv_rest  TYPE string,
        lv_num   TYPE i.

  CHECK core_object->lightspeed_info-supported = abap_false.

  SPLIT core_object->user_agent_info-version AT '.' INTO lv_major lv_rest.
  CHECK lv_major IS NOT INITIAL.
  CHECK lv_major CO '0123456789'.
  lv_num = lv_major.

  CASE core_object->user_agent_info-browser.
    WHEN 'Chrome'.
      CHECK lv_num >= 8.
      core_object->lightspeed_info-supported        = abap_true.
      core_object->lightspeed_info-renderer         = 'sf3'.
      core_object->lightspeed_info-lafservicedevice = 'sf3'.
      core_object->lightspeed_info-renderenginename = 'WebKit'.
      core_object->lightspeed_info-inlinecss        = abap_false.
    WHEN 'MSIE'.
      CHECK lv_num >= 6.
      CHECK core_object->user_agent_info-platform = 'Windows'.
      core_object->lightspeed_info-supported        = abap_true.
      core_object->lightspeed_info-renderer         = 'ie6'.
      core_object->lightspeed_info-lafservicedevice = 'ie6'.
      IF lv_num >= 7.
        core_object->lightspeed_info-requiresactivexforloadondemand = abap_false.
      ELSE.
        core_object->lightspeed_info-requiresactivexforloadondemand = abap_true.
      ENDIF.
    WHEN 'Firefox'.
      CHECK lv_num >= 4.
      core_object->lightspeed_info-supported        = abap_true.
      core_object->lightspeed_info-renderer         = 'ff1'.
      core_object->lightspeed_info-lafservicedevice = 'nn7'.
  ENDCASE.
```

**Verificación:** con el debugger se vio que IE11 queda como `MSIE / 11.0 / Windows / NT 10.0` y que `supported = X`. Después, "Start in Web Browser" con `sap-language=ES&SYSTEM_ID=BAS&...` carga DBACOCKPIT, con System Configuration, BAS y la estrella de Default.

**Vista de compatibilidad de IE (aplicada):** sin ella, Web Dynpro muestra *"The application was stopped due to a critical rendering error – Activate the compatibility mode in your Internet Explorer"* (nota 1586993). Se agregó `sapzrv.lab.local` en IE → Herramientas → Configuración de Vista de compatibilidad; IE lo guarda como `lab.local`. Con eso, "Start in Web Browser" abre DBACOCKPIT con `sap-language=ES` sin 500 y sin aviso.

**Ojo con los 500 "falsos":** recargar (F5) una ventana de IE vieja, cuya URL tiene parámetros de una sesión Web Dynpro que ya terminó (`...&SYSTEM_ID=BAS&ACTION...`), devuelve 500 sin dejar rastro en ST22, SM21 ni `dev_icf`. Para probar, siempre usar el botón "Start in Web Browser" o la URL limpia `.../dba_cockpit?sap-language=ES`.

**Deshacer:** SE24 → `CLUR_NW7_USER_AGENT_INFO` → Class → Enhance → borrar los post-exits o la implementación `ZE_UR_UA_VERSION100`.

## Checklist rápido para la próxima vez

1. ¿DBACOCKPIT en SAP GUI muestra el login de NetWeaver con "browser not supported"? → revisar `FEATURE_BROWSER_EMULATION` (Problema 1 / Paso 1d), sobre todo después de instalar o actualizar SAP GUI.
2. ¿Hay dump `CL_DBA_RDI=>GET_INSTANCE` llamado desde `SET_TEST_MODE`? → se entró sin sistema (navegador externo o perfil vacío). Verificar que `ZE_DB6_NAV_TESTMODE` esté activa y marcar Default System para el usuario.
3. ¿"Start in Web Browser" da 500 sin dump y `dev_icf` dice "This browser is not supported"? → verificar que `ZE_UR_UA_VERSION100` esté activa. Si es un navegador nuevo, ver su user agent con un breakpoint externo en `CLUR_NW7_USER_AGENT_INFO→SET_LIGHTSPEED_INFO`.
4. ¿Hay dump `CX_DBA_ROOT` / `CL_DB6_SYS` "Database of selected system is not supported"? → verificar que `ZE_DB6_SYS_SYB` siga activa (SPAU_ENH después de un SP).

## Herramientas usadas en esta sesión

| Herramienta | Para qué |
|---|---|
| regedit | Encontrar las entradas 11001 de SAP en `FEATURE_BROWSER_EMULATION` |
| ST22 | Dump, pila (Active Calls) y variables (`SYS_REF` initial) |
| SE80 → WD `DBA_COCKPIT` → vista `STARTUP` → `HANDLEINTO_STARTUP` | Lógica de arranque y llamada a `set_test_mode` |
| SE24 `CL_DB6_TREE_NAVIGATOR->SET_TEST_MODE`, `CL_DBA_USER_SESSION` | Origen del NULL y de dónde sale el sistema por defecto (`SPERS_OBJ`) |
| SE16 `SPERS_OBJ` (`PERS_KEY = DB6NAV`) | Personalización del cockpit por usuario (DDIC, SAP*, SAPADMIN) |
