# DBACOCKPIT en SAP NetWeaver 7.31 sobre Sybase ASE – correcciones

Correcciones para hacer funcionar **DBACOCKPIT** (dentro de SAP GUI y con "Start in Web Browser") en SAP NetWeaver 7.31 sobre Sybase ASE, sin notas de SAP: mejoras implícitas en ABAP, diffs contra el código estándar y guías paso a paso.

## Entorno

| Dato | Valor |
|---|---|
| Sistema | BAS (laboratorio), ECC6 EHP6 |
| SAP_BASIS | 731, kernel 722 |
| Base de datos | Sybase ASE 15.7 |
| SO / navegador | Windows 11, Internet Explorer 11 (lanzado por SAP GUI 770) |

## Mejoras

Todas son objetos locales (`$TMP`) y no modifican el código estándar.

| Mejora | Clase → método | Tipo | Síntoma que corrige |
|---|---|---|---|
| [`ZE_DB6_SYS_SYB`](enhancements/ZE_DB6_SYS_SYB/) | `CL_DB6_SYS→SYNCHRONIZE_SYSTEM_DATA` | Overwrite-Method | "Database of selected system is not supported": el `CASE` estándar no contempla `SYB` (dumps `SYSTEM_CLASSCONSTRUCTOR_FAILED`, `OBJECTS_OBJREF_NOT_ASSIGNED` en `CX_DBA_ROOT`). |
| [`ZE_DB6_NAV_TESTMODE`](enhancements/ZE_DB6_NAV_TESTMODE/) | `CL_DB6_TREE_NAVIGATOR→SET_TEST_MODE` | Overwrite-Method | Dump `OBJECTS_OBJREF_NOT_ASSIGNED` en `CL_DBA_RDI=>GET_INSTANCE` cuando el cockpit arranca sin sistema (navegador externo, usuario sin sistema por defecto). |
| [`ZE_UR_UA_VERSION100`](enhancements/ZE_UR_UA_VERSION100/) | `CLUR_NW7_USER_AGENT_INFO→SET_USER_AGENT_INFO` y `→SET_LIGHTSPEED_INFO` | Post-Methods | HTTP 500 "This browser is not supported": IE11 no manda "MSIE" en el user agent y las reglas comparan la versión como texto (`'11.0' < '6.0'`, `'155.0' < '8.0'`). |

Cada carpeta tiene el `.abap` completo de la implementación y el `.diff` contra el método estándar.

## Guías

- [`SAP731_SYBASE_DBACOCKPIT_FIX.md`](https://github.com/dev-lang/sap_time/blob/main/SAP731_SYBASE_DBACOCKPIT_FIX.md) (repo `sap_time`): HTTP 500 inicial: FQDN, servicios SICF, emulación de IE en SAP GUI y `ZE_DB6_SYS_SYB`.
- [`docs/SAP731_SYBASE_DBACOCKPIT_WEBBROWSER_WIN11_IE11_FIX.md`](docs/SAP731_SYBASE_DBACOCKPIT_WEBBROWSER_WIN11_IE11_FIX.md): regresión en Windows 11 y "Start in Web Browser": `FEATURE_BROWSER_EMULATION`, `ZE_DB6_NAV_TESTMODE`, `ZE_UR_UA_VERSION100` y la vista de compatibilidad de IE.

## Cómo recrear una mejora

1. SE24 → clase → Display → **Class → Enhance** → crear la implementación con el nombre de la carpeta → Local Object.
2. Seleccionar el método → **Edit → Enhancement Operations → Insert Overwrite-Method / Post-Method** → acceso a componentes privados: **Yes**.
3. Clic en el ícono de la columna Overwrite-Exit o PostExit → pegar el cuerpo del método del `.abap`.
4. Ctrl+F2 → Ctrl+S → Ctrl+F3, activando **sólo** la implementación.

Después de subir un support package de SAP_BASIS, revisar las tres en **SPAU_ENH**.

## Estructura

```
├── docs/
│   └── SAP731_SYBASE_DBACOCKPIT_WEBBROWSER_WIN11_IE11_FIX.md
└── enhancements/
    ├── ZE_DB6_SYS_SYB/         .abap + .diff
    ├── ZE_DB6_NAV_TESTMODE/    .abap + .diff
    └── ZE_UR_UA_VERSION100/    .abap + .diff
```
