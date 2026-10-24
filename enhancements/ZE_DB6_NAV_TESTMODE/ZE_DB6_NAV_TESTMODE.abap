*&---------------------------------------------------------------------*
*& Enhancement Implementation: ZE_DB6_NAV_TESTMODE  ($TMP)
*& Texto: DBACOCKPIT: SET_TEST_MODE sin sistema
*& Clase: CL_DB6_TREE_NAVIGATOR  -  Overwrite-Method SET_TEST_MODE
*&
*& Problema: si DBACOCKPIT arranca sin sistema resuelto ("Start in Web
*& Browser" sin sistema por defecto), STARTUP->HANDLEINTO_STARTUP llama
*& igual a SET_TEST_MODE, que pasa ME->SYSTEM (NULL) a
*& CL_DBA_RDI=>GET_INSTANCE -> OBJECTS_OBJREF_NOT_ASSIGNED.
*& Solucion: mismo metodo estandar + salida temprana si no hay sistema.
*&
*& Crear: SE24 CL_DB6_TREE_NAVIGATOR -> Class -> Enhance -> seleccionar
*& SET_TEST_MODE -> Edit -> Enhancement Operations -> Insert
*& Overwrite-Method (acceso a privados: Yes) -> pegar el cuerpo.
*&---------------------------------------------------------------------*
CLASS LCL_ZE_DB6_NAV_TESTMODE DEFINITION DEFERRED.
CLASS CL_DB6_TREE_NAVIGATOR DEFINITION LOCAL FRIENDS LCL_ZE_DB6_NAV_TESTMODE.
CLASS LCL_ZE_DB6_NAV_TESTMODE DEFINITION.
PUBLIC SECTION.
CLASS-DATA OBJ TYPE REF TO LCL_ZE_DB6_NAV_TESTMODE. "#EC NEEDED
DATA CORE_OBJECT TYPE REF TO CL_DB6_TREE_NAVIGATOR . "#EC NEEDED
 INTERFACES  IOW_ZE_DB6_NAV_TESTMODE.
  METHODS:
   CONSTRUCTOR IMPORTING CORE_OBJECT
     TYPE REF TO CL_DB6_TREE_NAVIGATOR OPTIONAL.
ENDCLASS.
CLASS LCL_ZE_DB6_NAV_TESTMODE IMPLEMENTATION.
METHOD CONSTRUCTOR.
  ME->CORE_OBJECT = CORE_OBJECT.
ENDMETHOD.

METHOD IOW_ZE_DB6_NAV_TESTMODE~SET_TEST_MODE.
*"------------------------------------------------------------------------*
*" Declaration of Overwrite-method, do not insert any comments here please!
*"
*"methods SET_TEST_MODE
*"  importing
*"    !TEST_MODE type STRING .
*"------------------------------------------------------------------------*

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

ENDMETHOD.
ENDCLASS.
