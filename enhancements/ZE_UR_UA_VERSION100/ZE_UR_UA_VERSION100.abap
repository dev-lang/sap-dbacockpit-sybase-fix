*&---------------------------------------------------------------------*
*& Enhancement Implementation: ZE_UR_UA_VERSION100  ($TMP)
*& Texto: WD: navegadores con version >= 100
*& Clase: CLUR_NW7_USER_AGENT_INFO
*&   - Post-Method SET_USER_AGENT_INFO  (reconoce IE11 / Trident rv:11)
*&   - Post-Method SET_LIGHTSPEED_INFO  (reglas con version numerica)
*&
*& Problema (Web Dynpro ABAP 7.31, "This browser is not supported"):
*&  1) IE11 en modo estandar manda
*&       Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko
*&     sin "MSIE": ninguna regex de SET_USER_AGENT_INFO lo reconoce.
*&  2) SET_LIGHTSPEED_INFO compara USER_AGENT_INFO-VERSION (TYPE string)
*&     como texto: 'version ge 8.0' / 'ge 6.0' -> '155.0' < '8.0',
*&     '11.0' < '6.0'. Toda version de 2-3 digitos queda rechazada.
*&
*& Crear: SE24 CLUR_NW7_USER_AGENT_INFO -> Class -> Enhance -> por cada
*& metodo: Edit -> Enhancement Operations -> Insert Post-Method
*& (acceso a privados: Yes) -> pegar el cuerpo.
*&---------------------------------------------------------------------*
CLASS LCL_ZE_UR_UA_VERSION100 DEFINITION DEFERRED.
CLASS CLUR_NW7_USER_AGENT_INFO DEFINITION LOCAL FRIENDS LCL_ZE_UR_UA_VERSION100.
CLASS LCL_ZE_UR_UA_VERSION100 DEFINITION.
PUBLIC SECTION.
CLASS-DATA OBJ TYPE REF TO LCL_ZE_UR_UA_VERSION100. "#EC NEEDED
DATA CORE_OBJECT TYPE REF TO CLUR_NW7_USER_AGENT_INFO . "#EC NEEDED
 INTERFACES  IPO_ZE_UR_UA_VERSION100.
  METHODS:
   CONSTRUCTOR IMPORTING CORE_OBJECT
     TYPE REF TO CLUR_NW7_USER_AGENT_INFO OPTIONAL.
ENDCLASS.
CLASS LCL_ZE_UR_UA_VERSION100 IMPLEMENTATION.
METHOD CONSTRUCTOR.
  ME->CORE_OBJECT = CORE_OBJECT.
ENDMETHOD.

METHOD IPO_ZE_UR_UA_VERSION100~SET_LIGHTSPEED_INFO.
*"------------------------------------------------------------------------*
*" Declaration of POST-method, do not insert any comments here please!
*"
*"methods SET_LIGHTSPEED_INFO .
*"------------------------------------------------------------------------*

  DATA: lv_major TYPE string,
        lv_rest  TYPE string,
        lv_num   TYPE i.

* Navegadores con version >= 100 (Chrome/Edge 1xx): la regla estandar
* compara la version como texto ('155.0' < '8.0') y los rechaza.
* Se reevalua usando la version mayor como numero.
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
*     IE11 (rv:11.0) llega aca como MSIE 11.0; la regla estandar
*     "MSIE >= 6.0" tambien compara texto ('11.0' < '6.0').
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

ENDMETHOD.

METHOD IPO_ZE_UR_UA_VERSION100~SET_USER_AGENT_INFO.
*"------------------------------------------------------------------------*
*" Declaration of POST-method, do not insert any comments here please!
*"
*"methods SET_USER_AGENT_INFO
*"  importing
*"    !USER_AGENT_STRING type STRING .
*"------------------------------------------------------------------------*

  DATA: lv_os TYPE string,
        lv_rv TYPE string.

* IE11 en modo estandar ya no manda "MSIE" en el user agent:
*   Mozilla/5.0 (Windows NT x.y; ...; Trident/7.0; rv:11.0) like Gecko
* y ninguna regla de 7.31 lo reconoce (queda "no soportado").
* Se lo identifica como MSIE con su version real (rv:).
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

ENDMETHOD.
ENDCLASS.
