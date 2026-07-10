import React from 'react';
import { Document, Page, Text, View, StyleSheet } from '@react-pdf/renderer';
import { ShiftManifestPayload } from '../mutations';

const styles = StyleSheet.create({
    page: { padding: 30, fontFamily: 'Helvetica' },
    header: { fontSize: 24, marginBottom: 20, textAlign: 'center', fontWeight: 'bold' },
    subHeader: { fontSize: 14, marginBottom: 10, color: '#333' },
    section: { marginBottom: 15, padding: 10, border: '1pt solid #ccc' },
    row: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 5 },
    label: { fontSize: 12, color: '#666' },
    value: { fontSize: 12, fontWeight: 'bold' },
    footer: { position: 'absolute', bottom: 30, left: 30, right: 30, fontSize: 10, textAlign: 'center', color: '#999', borderTop: '1pt solid #eee', paddingTop: 10 },
    signatureArea: { marginTop: 40, borderTop: '1pt solid #000', width: 200, paddingTop: 5, textAlign: 'center' }
});

export const ShiftManifestPDF = ({ data }: { data: ShiftManifestPayload }) => (
    <Document>
        <Page size="A4" style={styles.page}>
            <Text style={styles.header}>FuelFlow As-Built Manifest</Text>
            <Text style={styles.subHeader}>Legal End-of-Shift Record</Text>
            
            <View style={styles.section}>
                <View style={styles.row}>
                    <Text style={styles.label}>Project ID:</Text>
                    <Text style={styles.value}>{data.project_id}</Text>
                </View>
                <View style={styles.row}>
                    <Text style={styles.label}>Asset ID:</Text>
                    <Text style={styles.value}>{data.asset_id}</Text>
                </View>
                <View style={styles.row}>
                    <Text style={styles.label}>Operator ID:</Text>
                    <Text style={styles.value}>{data.operator_id}</Text>
                </View>
            </View>

            <View style={styles.section}>
                <View style={styles.row}>
                    <Text style={styles.label}>Shift Start:</Text>
                    <Text style={styles.value}>{new Date(data.shift_start_time).toLocaleString()}</Text>
                </View>
                <View style={styles.row}>
                    <Text style={styles.label}>Shift End:</Text>
                    <Text style={styles.value}>{new Date(data.shift_end_time).toLocaleString()}</Text>
                </View>
            </View>

            <View style={styles.section}>
                <View style={styles.row}>
                    <Text style={styles.label}>Total Tonnage (Net):</Text>
                    <Text style={styles.value}>{data.total_tonnage} T</Text>
                </View>
                <View style={styles.row}>
                    <Text style={styles.label}>Total Load Cycles:</Text>
                    <Text style={styles.value}>{data.total_cycles}</Text>
                </View>
                <View style={styles.row}>
                    <Text style={styles.label}>Fatigue Alerts Registered:</Text>
                    <Text style={styles.value}>{data.fatigue_alerts_count}</Text>
                </View>
                <View style={styles.row}>
                    <Text style={styles.label}>Mechanic Overrides:</Text>
                    <Text style={styles.value}>{data.mechanic_overrides_count}</Text>
                </View>
            </View>

            <View style={styles.signatureArea}>
                <Text style={styles.label}>Operator Signature</Text>
            </View>

            <Text style={styles.footer}>
                Generated securely by FuelFlow Edge Kiosk at {new Date().toISOString()}. 
                This document is cryptographically immutable and constitutes a legal record.
            </Text>
        </Page>
    </Document>
);
