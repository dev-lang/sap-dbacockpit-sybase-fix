*&---------------------------------------------------------------------*
*& Enhancement Implementation: ZE_DB6_SYS_SYB  ($TMP)
*& Texto: Soporte SYB DBACOCKPIT
*& Clase: CL_DB6_SYS  -  Overwrite-Method SYNCHRONIZE_SYSTEM_DATA
*& Fuente: include ZE_DB6_SYS_SYB================EIMP (SE38), sistema BAS,
*&         extraido el 24.10.2026.
*&
*& Problema: el CASE sys_data-dbsys del metodo estandar (SAP, 08.09.2011)
*& no tiene rama para 'SYB': Sybase cae en WHEN OTHERS -> RAISE cx_db6_sys
*& rc = x_wrong_database ("Database of selected system is not supported")
*& -> dumps SYSTEM_CLASSCONSTRUCTOR_FAILED / OBJECTS_OBJREF_NOT_ASSIGNED.
*& Solucion: copia del metodo estandar con  when 'ORA'.  ->  when 'ORA' or 'SYB'.
*& El resto son los ajustes para compilar dentro de la mejora
*& (me-> -> core_object->, constantes con cl_db6_sys=>, etc.).
*&
*& Crear: SE24 CL_DB6_SYS -> Class -> Enhance -> seleccionar
*& SYNCHRONIZE_SYSTEM_DATA -> Edit -> Enhancement Operations -> Insert
*& Overwrite-Method (acceso a privados: Yes) -> pegar el cuerpo.
*&---------------------------------------------------------------------*
CLASS LCL_ZE_DB6_SYS_SYB DEFINITION DEFERRED.
CLASS CL_DB6_SYS DEFINITION LOCAL FRIENDS LCL_ZE_DB6_SYS_SYB.
CLASS LCL_ZE_DB6_SYS_SYB DEFINITION.
PUBLIC SECTION.
CLASS-DATA OBJ TYPE REF TO LCL_ZE_DB6_SYS_SYB. "#EC NEEDED
DATA CORE_OBJECT TYPE REF TO CL_DB6_SYS . "#EC NEEDED
 INTERFACES  IOW_ZE_DB6_SYS_SYB.
  METHODS:
   CONSTRUCTOR IMPORTING CORE_OBJECT
     TYPE REF TO CL_DB6_SYS OPTIONAL.
ENDCLASS.
CLASS LCL_ZE_DB6_SYS_SYB IMPLEMENTATION.
METHOD CONSTRUCTOR.
  ME->CORE_OBJECT = CORE_OBJECT.
ENDMETHOD.

METHOD IOW_ZE_DB6_SYS_SYB~SYNCHRONIZE_SYSTEM_DATA.
*"------------------------------------------------------------------------*
*" Declaration of Overwrite-method, do not insert any comments here please!
*"
*"methods SYNCHRONIZE_SYSTEM_DATA
*"  raising
*"    CX_DB6_SYS .
*"------------------------------------------------------------------------*
*method synchronize_system_data .
*
  field-symbols:
    <db6pmsd>                type db6pmsd.
  data:
    rdi_excp                 type ref to cx_db6_rdi,
    adbc_excp                type ref to cx_dba_adbc,
    snapshot_table_refs      type db6cc_snapshot_table_list,
    snapshot_table_entry     type db6cc_snapshot_table_entry,
    it_db6pmsd               type table of db6pmsd,
    partition                type i,
    buffered_sysdata         type db6admsys,
    fw_ref                   type ref to cl_db6_tree_navigator,
    msg_list                 type dba_msg_list,
    old_sys_data             type db6navsyst,
    con_sys_data             type db6navsyst,
    rfc_sys_data             type db6navsyst,
    mss_connection_data      type mssconndata,
    mss_sqlrel               type mssconndata-sqlrelease,
    con_excp                 type ref to cx_db6_con,
    rfc_excp                 type ref to cx_dba_rfcdest,
    schemaname               type db6schema,
    dbsys                    type sydbsys,
    rc                       type sysubrc,
    rfc_error_message        type db6cc_rfc_message.

  data: dbh_setup            type ref to cl_dba_dbh_setup.
  data: ex_dbh_setup         type ref to cx_dba_dbh_setup.
*
  old_sys_data = core_object->sys_data.

  case core_object->get_connection_type( ).
    when cl_db6_sys=>contype_remote.
      try.
          con_sys_data = core_object->con_ref->get_system_basics( ).
          core_object->sys_data-realsid    = con_sys_data-realsid.
          core_object->sys_data-dbsys      = con_sys_data-dbsys.
          core_object->sys_data-dbrel      = con_sys_data-dbrel.
          core_object->sys_data-saprel     = con_sys_data-saprel.
          core_object->sys_data-dbhost     = con_sys_data-dbhost.
          core_object->sys_data-cockrel    = con_sys_data-cockrel.
          core_object->sys_data-schemaname = con_sys_data-schemaname.
          core_object->sys_data-dbsid      = con_sys_data-dbsid.
        catch cx_db6_con into con_excp.
          raise exception type cx_db6_sys
            exporting
              method_name = 'SYNCHRONIZE_SYSTEM_DATA'
              rc          = con_excp->rc.
      endtry.
*
*
    when cl_db6_sys=>contype_remote_via_rfc.
      call function 'SMSS_TEST_CONNECT'
        destination core_object->sys_data-rfcdest
        exporting
          rfcdest               = core_object->sys_data-rfcdest
          con_name              = core_object->sys_data-dbcname
          abap_check            = ' '
        importing
          testcon               = mss_connection_data
        exceptions
          system_failure        = cl_db6_rc=>x_system_failure  message rfc_error_message
          communication_failure = cl_db6_rc=>x_communication_failure  message rfc_error_message
          c_call_failed         = cl_db6_rc=>x_c_call_failed
          adbc_error            = cl_db6_rc=>x_adbc_error
          others                = cl_db6_rc=>x_others.
      case sy-subrc.

        when cl_db6_rc=>x_system_failure         or
             cl_db6_rc=>x_communication_failure.
          rc = sy-subrc.
          raise exception type cx_db6_sys
            exporting
              method_name   = 'SYNCHRONIZE_SYSTEM_DATA'
              function_unit = 'SMSS_TEST_CONNECT'
              sysid         = core_object->sys_data-sysid
              rc            = rc
              rfc_message   = rfc_error_message.

        when 0.
          if mss_connection_data-msgty ca 'EA'.
            raise exception type cx_db6_sys
              exporting
                method_name   = 'SYNCHRONIZE_SYSTEM_DATA'
                function_unit = 'SMSS_TEST_CONNECT'
                sysid         = core_object->sys_data-sysid
                rc            = cl_db6_rc=>x_system_not_reached.
          else.
            core_object->sys_data-realsid = mss_connection_data-dbname.
            mss_sqlrel = cl_mss_dbcon=>format_dbrel( mss_connection_data-sqlrelease ).
            core_object->sys_data-dbrel = mss_sqlrel(10).
            core_object->sys_data-saprel = mss_connection_data-saprelease.
            core_object->sys_data-dbhost = mss_connection_data-hostname.
            core_object->sys_data-schemaname = mss_connection_data-dbschema.
            core_object->sys_data-dbsid = mss_connection_data-dbname.
            core_object->sys_data-cockrel    = '711'.
            core_object->sys_data-dbsys      = 'MSS'.
          endif.
        when others.
          rc = sy-subrc.
          raise exception type cx_db6_sys
            exporting
              method_name   = 'SMSS_TEST_CONNECT'
              function_unit = 'DB6_DIAG_GET_SYSTEM_BASICS'
              sysid         = core_object->sys_data-sysid
              rc            = rc.
      endcase.
    when cl_db6_sys=>contype_remote_and_rfc.
      try.
          rfc_sys_data = core_object->rfc_ref->get_system_basics( ).
          con_sys_data = core_object->con_ref->get_system_basics( ).
          if con_sys_data-dbsys <> rfc_sys_data-dbsys or
             con_sys_data-dbhost <> rfc_sys_data-dbhost or
             con_sys_data-dbsid  <> rfc_sys_data-dbsid or
             con_sys_data-schemaname <> rfc_sys_data-schemaname.
*          deviation
          endif.
          core_object->sys_data-realsid    = con_sys_data-realsid.
          core_object->sys_data-dbsys      = con_sys_data-dbsys.
          core_object->sys_data-dbrel      = con_sys_data-dbrel.
          core_object->sys_data-saprel     = con_sys_data-saprel.
          core_object->sys_data-dbhost     = con_sys_data-dbhost.
          core_object->sys_data-cockrel    = con_sys_data-cockrel.
          core_object->sys_data-schemaname = con_sys_data-schemaname.
          core_object->sys_data-dbsid      = con_sys_data-dbsid.
        catch cx_db6_con into con_excp.
          raise exception type cx_db6_sys
            exporting
              method_name = 'SYNCHRONIZE_SYSTEM_DATA'
              rc          = con_excp->rc.
        catch cx_dba_rfcdest into rfc_excp.
      endtry.
    when cl_db6_sys=>contype_rfc.
      try.
          rfc_sys_data = core_object->rfc_ref->get_system_basics( ).
          core_object->sys_data-realsid    = rfc_sys_data-realsid.
          core_object->sys_data-dbsys      = rfc_sys_data-dbsys.
          core_object->sys_data-dbrel      = rfc_sys_data-dbrel.
          core_object->sys_data-saprel     = rfc_sys_data-saprel.
          core_object->sys_data-dbhost     = rfc_sys_data-dbhost.
          core_object->sys_data-cockrel    = rfc_sys_data-cockrel.
          core_object->sys_data-schemaname = rfc_sys_data-schemaname.
          core_object->sys_data-dbsid      = rfc_sys_data-dbsid.
        catch cx_dba_rfcdest into rfc_excp.
          raise exception type cx_db6_sys
            exporting
              method_name = 'SYNCHRONIZE_SYSTEM_DATA'
              rc          = rfc_excp->rc.
      endtry.

    when cl_db6_sys=>contype_local.
      call function 'DB6_DIAG_GET_SYSTEM_BASICS'
        importing
          sysid         = core_object->sys_data-realsid
          dbsys         = dbsys
          dbrel         = core_object->sys_data-dbrel
          basrel        = core_object->sys_data-saprel
          dbserver      = core_object->sys_data-dbhost
          cockrel       = core_object->sys_data-cockrel
          schemaname    = schemaname
          dbname        = core_object->sys_data-dbsid
        exceptions
          c_call_failed = cl_db6_rc=>x_c_call_failed
          adbc_error    = cl_db6_rc=>x_adbc_error
          others        = cl_db6_rc=>x_others.
      if sy-subrc <> 0.
        rc = sy-subrc.
        raise exception type cx_db6_sys
          exporting
            method_name   = 'SYNCHRONIZE_SYSTEM_DATA'
            function_unit = 'DB6_DIAG_GET_SYSTEM_BASICS'
            sysid         = core_object->sys_data-sysid
            rc            = rc.
      else.
        core_object->sys_data-dbsys      = dbsys.
        core_object->sys_data-schemaname = schemaname.
        if core_object->sys_data-dbsys = 'ADA'.
          core_object->sys_data-dbcname = cl_db6_sys=>local_sysid.
        endif.
      endif.

    when cl_db6_sys=>contype_cross_schema.
      call function 'DB6_DIAG_GET_SYSTEM_BASICS'
        importing
          sysid         = core_object->sys_data-realsid
          dbsys         = dbsys
          dbrel         = core_object->sys_data-dbrel
          dbserver      = core_object->sys_data-dbhost
          cockrel       = core_object->sys_data-cockrel
          dbname        = core_object->sys_data-dbsid
        exceptions
          c_call_failed = cl_db6_rc=>x_c_call_failed
          adbc_error    = cl_db6_rc=>x_adbc_error
          others        = cl_db6_rc=>x_others.
      if sy-subrc <> 0.
        rc = sy-subrc.
        raise exception type cx_db6_sys
          exporting
            method_name   = 'SYNCHRONIZE_SYSTEM_DATA'
            function_unit = 'DB6_DIAG_GET_SYSTEM_BASICS'
            sysid         = core_object->sys_data-sysid
            rc            = rc.
      else.
        core_object->sys_data-dbsys      = dbsys.
      endif.

  endcase.

* Check system credentials
  if core_object->sys_data-cockrel is initial.
    raise exception type cx_db6_sys
      exporting
        method_name = 'SYNCHRONIZE_SYSTEM_DATA'
        sysid       = core_object->sys_data-sysid
        rc          = cl_db6_rc=>x_wrong_cockrel.
  endif.

  if ( core_object->get_connection_type( )               = cl_db6_sys=>contype_local        and
       core_object->is_supported_db( core_object->sys_data-dbsys )             = abap_false               ) or
     ( core_object->get_connection_type( )               = cl_db6_sys=>contype_rfc          and
       core_object->is_supported_rfc_db( core_object->sys_data-dbsys )         = abap_false               ) or
     ( core_object->get_connection_type( )               = cl_db6_sys=>contype_remote       and
       cl_dba_dbcon=>is_supported_db( core_object->sys_data-dbsys ) = abap_false               ) or
     ( core_object->get_connection_type( )               = cl_db6_sys=>contype_cross_schema and
       core_object->is_supported_cross_schema( core_object->sys_data-dbsys )   = abap_false               ).
    raise exception type cx_db6_sys
      exporting
        method_name = 'SYNCHRONIZE_SYSTEM_DATA'
        sysid       = core_object->sys_data-sysid
        rc          = cl_db6_rc=>x_wrong_database.
  endif.

  if core_object->get_connection_type( ) = cl_db6_sys=>contype_remote and
     core_object->is_supported_db_release( dbsys   = core_object->sys_data-dbsys
                              contype = cl_db6_sys=>contype_remote
                              dbrel = core_object->sys_data-dbrel ) = abap_false.
    dbsys = core_object->sys_data-dbsys.
    raise exception type cx_db6_sys
      exporting
        method_name = 'SYNCHRONIZE_SYSTEM_DATA'
        sysid       = core_object->sys_data-sysid
        dbrel       = core_object->sys_data-dbrel
        dbsys       = dbsys
        contype     = cl_db6_sys=>contype_remote
        rc          = cl_db6_rc=>x_wrong_dbrel.
  endif.
  if core_object->get_connection_type( ) = cl_db6_sys=>contype_cross_schema.
    clear core_object->sys_data-saprel.
  endif.

  core_object->sys_data-entrystate = cl_db6_sys=>sysentry_complete.

  if core_object->sys_data-saprel is initial.
    core_object->sys_data-entrytype = cl_db6_sys=>systype_native.
  else.
    core_object->sys_data-entrytype = cl_db6_sys=>systype_r3.
  endif.


  case core_object->sys_data-dbsys.
    when 'ADA'.
    when 'DB6'.

      if core_object->sys_data-db_opsys is initial.
        core_object->sys_data-db_opsys = db6cc_opsys_unknown.
      endif.

      try.
          snapshot_table_entry-name = 'DB6PMSD'.
          get reference of it_db6pmsd[] into snapshot_table_entry-ref.
          append snapshot_table_entry to snapshot_table_refs.
          partition = cl_db6_syscat=>get_1st_partition( sys_ref = core_object ).
          cl_db6_rdi=>get_snapshot( action     = db6cc_action_get_data
                                    callerflag = db6cc_caller_user
                                    partition  = partition
                                    connection = core_object->sys_data-dbcname
                                    snapshot_table_list = snapshot_table_refs ).
          read table it_db6pmsd index 1 assigning <db6pmsd>.
          if sy-subrc = 0.
            core_object->sys_data-dbsid = <db6pmsd>-dbname.
            case <db6pmsd>-serv_platf.
              when 'NT'.
                core_object->sys_data-db_opsys = db6cc_opsys_windows_nt.
              when 'Sun'.
                core_object->sys_data-db_opsys = db6cc_opsys_sun.
              when 'AIX'.
                core_object->sys_data-db_opsys = db6cc_opsys_aix.
              when 'Linux'.
                core_object->sys_data-db_opsys = db6cc_opsys_linux.
              when 'HP'.
                core_object->sys_data-db_opsys = db6cc_opsys_hpux.
              when others.
            endcase.
          endif.
*       Ignore errors here
        catch cx_db6_rdi into rdi_excp.
        catch cx_dba_adbc into adbc_excp.
      endtry.
    when 'DB2'.
    when 'DB4'.
    when 'MSS'.
      core_object->sys_data-db_opsys = db6cc_opsys_windows_nt.
      core_object->sys_data-entrytype = cl_db6_sys=>systype_native.  " This is to avoid error in DETERMINE_SYSTEM_TYPE when the schema is dbo
    when 'ORA' or 'SYB'.
    when others.
      raise exception type cx_db6_sys
        exporting
          method_name = 'SYNCHRONIZE_SYSTEM_DATA'
          sysid       = core_object->sys_data-sysid
          rc          = cl_db6_rc=>x_wrong_database.
  endcase.

  core_object->migrate_old_entries( ).

  try.
      core_object->determine_system_type( ).
    catch cx_dba_adbc into adbc_excp.
      raise exception type cx_db6_sys
        exporting
          method_name = 'SYNCHRONIZE_SYSTEM_DATA'
          sysid       = core_object->sys_data-sysid
          previous    = adbc_excp
          rc          = cl_db6_rc=>x_adbc_error.
  endtry.
*
  core_object->adm_data-synchronized = abap_true.
  if core_object->sys_data <> old_sys_data.
    core_object->adm_data-changed = abap_true.
    core_object->adm_data-moddate = sy-datum.
    core_object->adm_data-modtime = sy-uzeit.
  else.
    move-corresponding core_object->sys_data to buffered_sysdata.
    move-corresponding core_object->adm_data to buffered_sysdata.
    modify table cl_db6_sys=>systems from buffered_sysdata transporting synchronized.
  endif.

  try.
      dbh_setup = cl_dba_dbh_setup=>get_instance( sys_ref = core_object ).
      dbh_setup->synchronize_offline_info( ).
    catch cx_dba_dbh_setup into ex_dbh_setup.           "#EC NO_HANDLER
    catch cx_dba_dbh_not_supported.                     "#EC NO_HANDLER
  endtry.
*
*endmethod.

ENDMETHOD.
ENDCLASS.
