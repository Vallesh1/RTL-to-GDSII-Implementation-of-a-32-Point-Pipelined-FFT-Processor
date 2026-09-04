set NDM_LIBS {}
set FRAME_LIBS {/home1/14_nmts/14_nmts/stdcell_rvt/ndm/saed14rvt_frame_only.ndm}
set LEF_FILES {}
set DB_FILES {/home1/14_nmts/14_nmts/stdcell_rvt/db_ccs/saed14rvt_ff0p7vm40c.db /home1/14_nmts/14_nmts/stdcell_rvt/db_ccs/saed14rvt_ss0p6v125c.db}
set TECH_FILE "/home1/14_nmts/14_nmts/tech/milkyway/saed14nm_1p9m_mw.tf"

set_app_options -name lib.workspace.create_cached_lib -value true
#suppress_messages

set_app_options -name lib.workspace.allow_read_aggregate_lib -value true
create_workspace saed14rvt_c -scale_factor 10000
foreach frame $FRAME_LIBS {
  read_ndm $frame
}
read_db $DB_FILES
process_workspaces -check_options {-allow_missing} -force -directory CLIBs -output saed14rvt_c.ndm
