import streamlit as st
import pandas as pd
from pathlib import Path

st.set_page_config(layout="wide", page_title="Arabic ASR Annotation Tool")
st.title("🎧 Arabic ASR Data Review Tool")

st.markdown("""
<style>
div[data-testid="stTextArea"] textarea {
    direction: rtl !important;
    text-align: right !important;
    unicode-bidi: plaintext !important;
}
</style>
""", unsafe_allow_html=True)

# Setup paths (Adjust these to match your dataset folder)
DATASET_DIR = Path("../dataset")

# Find all chunk_metadata.csv files dynamically
csv_files = sorted(list(DATASET_DIR.glob("**/chunk_metadata.csv")))

if not csv_files:
    st.error("❌ No chunk_metadata.csv files found. Please check your data directory structure.")
else:
    # 1. Selection Sidebar
    st.sidebar.header("📁 Navigation")
    selected_csv = st.sidebar.selectbox(
        "Select Lecture:", 
        csv_files, 
        format_func=lambda x: f"Lecture: {x.parent.name} ({x.parent.parent.name})"
    )
    
    # Load the selected CSV
    df = pd.read_csv(selected_csv)

    # Crucial step: Initialize the 'status' column if it's completely missing
    if "status" not in df.columns:
        df["status"] = "valid"  # Default everything to valid first

    # Sidebar: filters and controls
    st.sidebar.subheader("Filters & Settings")
    status_filter = st.sidebar.selectbox("Filter by status:", options=["all", "valid", "noise"], index=0)
    autosave = st.sidebar.checkbox("Autosave changes", value=False)
    search_query = st.sidebar.text_input("Search transcripts (substring):", value="")

    # Build list of indices matching current filters (preserve original df indices)
    def _matches(i):
        if status_filter != "all" and str(df.at[i, "status"]) != status_filter:
            return False
        if search_query:
            return search_query.lower() in str(df.at[i, "text"]).lower()
        return True

    filtered_indices = [i for i in df.index if _matches(i)]
    total_chunks = len(filtered_indices)

    # Track the current position within the filtered list using session state
    if "current_filtered_pos" not in st.session_state:
        st.session_state.current_filtered_pos = 0

    # Reset position if they switch lectures
    if "last_loaded" not in st.session_state or st.session_state.last_loaded != selected_csv:
        st.session_state.current_filtered_pos = 0
        st.session_state.last_loaded = selected_csv

    # If filters changed and current pos is out-of-range, reset
    if st.session_state.current_filtered_pos >= total_chunks:
        st.session_state.current_filtered_pos = 0

    # Sidebar: quick jump to a specific chunk by filtered number
    jump_label = f"Go to chunk # (1-{max(1, total_chunks)})"
    jump_to = st.sidebar.number_input(jump_label, min_value=1, max_value=max(1, total_chunks), value=st.session_state.current_filtered_pos + 1, step=1)
    if st.sidebar.button("Go") and total_chunks > 0:
        st.session_state.current_filtered_pos = int(jump_to) - 1
        st.rerun()

    # Map filtered position to actual dataframe index
    if total_chunks == 0:
        st.warning("No chunks match the current filter/search.")
        # Show nothing else for this lecture
        st.stop()

    real_idx = filtered_indices[st.session_state.current_filtered_pos]
    
    # 2. Top Controls / Navigation
    col1, col2, col3 = st.columns([1, 2, 1])
    with col1:
        if st.button("⬅ Previous Chunk") and st.session_state.current_filtered_pos > 0:
            st.session_state.current_filtered_pos -= 1
            st.rerun()
    with col2:
        st.markdown(f"<h3 style='text-align: center;'>Chunk {st.session_state.current_filtered_pos + 1} of {total_chunks}</h3>", unsafe_allow_html=True)
    with col3:
        if st.button("Next Chunk ➡") and st.session_state.current_filtered_pos < total_chunks - 1:
            st.session_state.current_filtered_pos += 1
            st.rerun()
            
    st.markdown("---")
    
    # Get current row data
    row = df.loc[real_idx]
    
    # Locate the audio file relative to this csv
    lecture_folder = selected_csv.parent
    audio_path = lecture_folder / "chunks" / row["chunk_file"]
    
    # 3. Main Interface Layout
    main_col, side_col = st.columns([2, 1])
    
    with main_col:
        st.subheader("🔊 Audio Player")
        if audio_path.exists():
            st.audio(str(audio_path), format="audio/wav")
        else:
            st.error(f"File not found: {audio_path.name} at {audio_path.parent}")
            
        st.subheader("📝 Text Transcription")
        # Let annotators fix any typos or mistranslations directly here
        edited_text = st.text_area("Edit text if needed (Arabic / Technical Terms):", value=str(row["text"]), height=120)
        df.at[real_idx, "text"] = edited_text
        if autosave:
            df.to_csv(selected_csv, index=False)
            st.toast("Progress autosaved to CSV!", icon="✅")
        
    with side_col:
        st.subheader("🏷 Categorize Status")
        
        # Radio choices matching the design framework
        status_options = ["valid", "noise"]
        
        # Ensure fallback index if the cell contains something unexpected
        current_status = row["status"] if row["status"] in status_options else "valid"
        default_status_idx = status_options.index(current_status)
        
        chosen_status = st.radio(
            "Select the audio classification:",
            options=status_options,
            index=default_status_idx,
            help="Valid = Clear/Usable speech. Noise = Pure Noise."
        )
        
        # Write choice directly to DataFrame state
        df.at[real_idx, "status"] = chosen_status
        if autosave:
            df.to_csv(selected_csv, index=False)
            st.toast("Progress autosaved to CSV!", icon="✅")
        
        st.markdown("<br>", unsafe_allow_html=True)
        
        # Save Button triggers file overwrite
        if st.button("💾 Save Progress", type="primary", use_container_width=True):
            df.to_csv(selected_csv, index=False)
            st.toast("Progress saved to CSV!", icon="✅")
            # Move to next chunk after saving (if available)
            if st.session_state.current_filtered_pos < total_chunks - 1:
                st.session_state.current_filtered_pos += 1
                st.rerun()
            else:
                st.info("You have reached the last chunk for this filter/lecture.")

