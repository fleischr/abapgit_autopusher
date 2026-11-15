*&---------------------------------------------------------------------*
*& Report ZABAPGIT_AUTOPUSH
*&---------------------------------------------------------------------*
*& Pushes all local additions/modifications of one abapGit online
*& repository to a given branch. Files that exist only in Git are
*& never deleted - they are listed for manual review.
*&
*& Runs in dialog (SE38/SA38) or as a daily background job (SM36 with
*& a variant). Requires the abapGit developer version (full package)
*& in the system - the standalone ZABAPGIT program is not sufficient.
*&
*& abapGit API calls mirror ZCL_ABAPGIT_BACKGROUND_PUSH_FI and
*& ZCL_ABAPGIT_BACKGROUND. If the installed abapGit release differs,
*& align the calls with those two classes.
*&---------------------------------------------------------------------*
REPORT zabapgit_autopush LINE-SIZE 255.

SELECTION-SCREEN BEGIN OF BLOCK b_repo WITH FRAME TITLE TEXT-001.
PARAMETERS: p_url    TYPE c LENGTH 255 LOWER CASE OBLIGATORY,
            p_pack   TYPE devclass OBLIGATORY,
            p_branch TYPE c LENGTH 100 LOWER CASE OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_repo.

SELECTION-SCREEN BEGIN OF BLOCK b_auth WITH FRAME TITLE TEXT-002.
PARAMETERS: p_user  TYPE c LENGTH 100 LOWER CASE OBLIGATORY,
            p_token TYPE c LENGTH 255 LOWER CASE OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_auth.

SELECTION-SCREEN BEGIN OF BLOCK b_comm WITH FRAME TITLE TEXT-003.
PARAMETERS: p_name  TYPE c LENGTH 100 LOWER CASE OBLIGATORY,
            p_email TYPE c LENGTH 100 LOWER CASE OBLIGATORY,
            p_msg   TYPE c LENGTH 255 LOWER CASE OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b_comm.

SELECTION-SCREEN BEGIN OF BLOCK b_opt WITH FRAME TITLE TEXT-004.
PARAMETERS p_test AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b_opt.

*----------------------------------------------------------------------*
CLASS lcl_autopush DEFINITION FINAL.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_params,
        url     TYPE string,
        package TYPE devclass,
        branch  TYPE string,
        user    TYPE string,
        token   TYPE string,
        name    TYPE string,
        email   TYPE string,
        message TYPE string,
        test    TYPE abap_bool,
      END OF ty_params.

    METHODS constructor
      IMPORTING
        is_params TYPE ty_params.

    METHODS run.

  PRIVATE SECTION.
    CONSTANTS c_branch_prefix TYPE string VALUE 'refs/heads/'.

    DATA: ms_params          TYPE ty_params,
          mi_repo            TYPE REF TO zif_abapgit_repo_online,
          mv_original_branch TYPE string,
          mv_branch_switched TYPE abap_bool,
          mo_stage           TYPE REF TO zcl_abapgit_stage,
          ms_files           TYPE zif_abapgit_definitions=>ty_stage_files,
          mt_objects         TYPE string_table,
          ms_comment         TYPE zif_abapgit_git_definitions=>ty_comment.

    METHODS validate
      RAISING
        zcx_abapgit_exception.

    METHODS find_repo
      RAISING
        zcx_abapgit_exception.

    METHODS set_login
      RAISING
        zcx_abapgit_exception.

    METHODS switch_branch
      RAISING
        zcx_abapgit_exception.

    METHODS stage_changes
      RETURNING
        VALUE(rv_staged) TYPE abap_bool
      RAISING
        zcx_abapgit_exception.

    METHODS build_comment.

    METHODS cleanup
      RETURNING
        VALUE(rv_error) TYPE string.

    METHODS write_header.

    METHODS write_files.

    METHODS report_error
      IMPORTING
        iv_text TYPE string.

ENDCLASS.

*----------------------------------------------------------------------*
CLASS lcl_autopush IMPLEMENTATION.

  METHOD constructor.

    ms_params = is_params.

    CONDENSE: ms_params-url,
              ms_params-branch,
              ms_params-user,
              ms_params-email.

    IF ms_params-branch NP 'refs/heads/*'.
      ms_params-branch = c_branch_prefix && ms_params-branch.
    ENDIF.

  ENDMETHOD.


  METHOD run.

    DATA: lx_error         TYPE REF TO zcx_abapgit_exception,
          lv_error         TYPE string,
          lv_cleanup_error TYPE string.

    write_header( ).

    TRY.
        validate( ).
        find_repo( ).
        set_login( ).
        switch_branch( ).

        IF stage_changes( ) = abap_false.
          write_files( ).
          WRITE / TEXT-022.
        ELSE.
          build_comment( ).
          write_files( ).
          IF ms_params-test = abap_true.
            WRITE / TEXT-024.
          ELSE.
            mi_repo->push( is_comment = ms_comment
                           io_stage   = mo_stage ).
            WRITE / TEXT-023.
          ENDIF.
        ENDIF.

      CATCH zcx_abapgit_exception INTO lx_error.
        lv_error = lx_error->get_text( ).
    ENDTRY.

    " Always restore the original branch and drop the credentials,
    " whether the push succeeded or not
    lv_cleanup_error = cleanup( ).
    IF lv_cleanup_error IS NOT INITIAL.
      IF lv_error IS INITIAL.
        lv_error = lv_cleanup_error.
      ELSE.
        lv_error = |{ lv_error } / { lv_cleanup_error }|.
      ENDIF.
    ENDIF.

    IF lv_error IS NOT INITIAL.
      report_error( lv_error ).
    ENDIF.

  ENDMETHOD.


  METHOD validate.

    DATA lv_devclass TYPE devclass.

    IF ms_params-url NP 'https://*'.
      zcx_abapgit_exception=>raise( TEXT-030 ).
    ENDIF.

    FIND REGEX '^[^@\s]+@[^@\s]+\.[^@\s]+$' IN ms_params-email.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( TEXT-031 ).
    ENDIF.

    SELECT SINGLE devclass FROM tdevc
      INTO @lv_devclass
      WHERE devclass = @ms_params-package.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( |{ TEXT-032 } { ms_params-package }| ).
    ENDIF.

  ENDMETHOD.


  METHOD find_repo.

    DATA: li_repo   TYPE REF TO zif_abapgit_repo,
          lv_reason TYPE string.

    zcl_abapgit_repo_srv=>get_instance( )->get_repo_from_url(
      EXPORTING
        iv_url    = ms_params-url
      IMPORTING
        ei_repo   = li_repo
        ev_reason = lv_reason ).

    IF li_repo IS NOT BOUND.
      zcx_abapgit_exception=>raise( |{ TEXT-036 } { lv_reason }| ).
    ENDIF.

    TRY.
        mi_repo ?= li_repo.
      CATCH cx_sy_move_cast_error.
        zcx_abapgit_exception=>raise( TEXT-033 ).
    ENDTRY.

    " URL and package must point to the same abapGit repository
    IF li_repo->get_package( ) <> ms_params-package.
      zcx_abapgit_exception=>raise( |{ TEXT-034 } { li_repo->get_package( ) }| ).
    ENDIF.

  ENDMETHOD.


  METHOD set_login.

    " Same mechanism ZCL_ABAPGIT_BACKGROUND uses - no login popup
    zcl_abapgit_login_manager=>set_basic(
      iv_uri      = mi_repo->get_url( )
      iv_username = ms_params-user
      iv_password = ms_params-token ).

  ENDMETHOD.


  METHOD switch_branch.

    mv_original_branch = mi_repo->get_selected_branch( ).

    IF mv_original_branch <> ms_params-branch.
      " Flag first, so cleanup restores even if the switch fails halfway
      mv_branch_switched = abap_true.
      mi_repo->select_branch( ms_params-branch ).
    ENDIF.

    " Aborts if the branch does not exist - branches are never created
    mi_repo->check_for_valid_branch( ).

  ENDMETHOD.


  METHOD stage_changes.

    FIELD-SYMBOLS <ls_local> LIKE LINE OF ms_files-local.

    ms_files = zcl_abapgit_stage_logic=>get_stage_logic( )->get( mi_repo ).

    CREATE OBJECT mo_stage.

    " Only local additions/modifications are staged. Remote-only files
    " (ms_files-remote) are deliberately NOT removed, so work pushed by
    " other developers to the shared branch is never deleted.
    LOOP AT ms_files-local ASSIGNING <ls_local>.
      mo_stage->add( iv_path     = <ls_local>-file-path
                     iv_filename = <ls_local>-file-filename
                     iv_data     = <ls_local>-file-data ).

      IF <ls_local>-item-obj_type IS NOT INITIAL.
        APPEND |{ <ls_local>-item-obj_type } { <ls_local>-item-obj_name }| TO mt_objects.
      ELSE.
        APPEND |{ <ls_local>-file-path }{ <ls_local>-file-filename }| TO mt_objects.
      ENDIF.
    ENDLOOP.

    SORT mt_objects.
    DELETE ADJACENT DUPLICATES FROM mt_objects.

    rv_staged = boolc( ms_files-local IS NOT INITIAL ).

  ENDMETHOD.


  METHOD build_comment.

    DATA: lv_date      TYPE d,
          lv_time      TYPE t,
          lv_timestamp TYPE string,
          lv_user      TYPE string,
          lv_message   TYPE string,
          lv_object    TYPE string.

    lv_date = sy-datum.
    lv_time = sy-uzeit.
    lv_timestamp = |{ lv_date DATE = ISO } { lv_time TIME = ISO }|.
    lv_user = sy-uname.

    lv_message = ms_params-message.
    REPLACE ALL OCCURRENCES OF '&timestamp' IN lv_message WITH lv_timestamp.
    REPLACE ALL OCCURRENCES OF '&user' IN lv_message WITH lv_user.

    " Body: blank line + one line per staged object
    lv_message = |{ lv_message }\n|.
    LOOP AT mt_objects INTO lv_object.
      lv_message = |{ lv_message }\n{ lv_object }|.
    ENDLOOP.

    ms_comment-committer-name  = ms_params-name.
    ms_comment-committer-email = ms_params-email.
    ms_comment-author-name     = ms_params-name.
    ms_comment-author-email    = ms_params-email.
    ms_comment-comment         = lv_message.

  ENDMETHOD.


  METHOD cleanup.

    DATA lx_error TYPE REF TO zcx_abapgit_exception.

    IF mv_branch_switched = abap_true AND mv_original_branch IS NOT INITIAL.
      TRY.
          mi_repo->select_branch( mv_original_branch ).
        CATCH zcx_abapgit_exception INTO lx_error.
          rv_error = |{ TEXT-035 } { mv_original_branch }: { lx_error->get_text( ) }|.
      ENDTRY.
    ENDIF.

    zcl_abapgit_login_manager=>clear( ).

  ENDMETHOD.


  METHOD write_header.

    WRITE: / |{ TEXT-010 } { ms_params-url }|,
           / |{ TEXT-011 } { ms_params-package }|,
           / |{ TEXT-012 } { ms_params-branch }|.

    IF ms_params-test = abap_true.
      WRITE / |{ TEXT-013 } { TEXT-014 }|.
    ELSE.
      WRITE / |{ TEXT-013 } { TEXT-015 }|.
    ENDIF.

    ULINE.

  ENDMETHOD.


  METHOD write_files.

    DATA lv_object TYPE string.

    FIELD-SYMBOLS <ls_remote> LIKE LINE OF ms_files-remote.

    IF mt_objects IS NOT INITIAL.
      WRITE / TEXT-020.
      LOOP AT mt_objects INTO lv_object.
        WRITE /3 lv_object.
      ENDLOOP.
      SKIP.
    ENDIF.

    IF ms_files-remote IS NOT INITIAL.
      WRITE / TEXT-021.
      LOOP AT ms_files-remote ASSIGNING <ls_remote>.
        WRITE /3 |{ <ls_remote>-path }{ <ls_remote>-filename }|.
      ENDLOOP.
      SKIP.
    ENDIF.

  ENDMETHOD.


  METHOD report_error.

    WRITE / |{ TEXT-025 } { iv_text }|.

    IF sy-batch = abap_true.
      " Cancels the job so the failure is visible in SM37
      MESSAGE iv_text TYPE 'E'.
    ELSE.
      MESSAGE iv_text TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.

  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
DATA gs_params TYPE lcl_autopush=>ty_params.
DATA go_autopush TYPE REF TO lcl_autopush.

INITIALIZATION.
  p_msg = TEXT-040.

AT SELECTION-SCREEN OUTPUT.
  " Show the token as ***** on the selection screen
  LOOP AT SCREEN.
    IF screen-name = 'P_TOKEN'.
      screen-invisible = '1'.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

START-OF-SELECTION.
  gs_params-url     = p_url.
  gs_params-package = p_pack.
  gs_params-branch  = p_branch.
  gs_params-user    = p_user.
  gs_params-token   = p_token.
  gs_params-name    = p_name.
  gs_params-email   = p_email.
  gs_params-message = p_msg.
  gs_params-test    = p_test.

  CREATE OBJECT go_autopush
    EXPORTING
      is_params = gs_params.

  go_autopush->run( ).
