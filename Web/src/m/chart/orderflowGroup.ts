// 移植自 KanpanChart/Sources/KanpanChart/OrderFlowGroup.swift
// （占位：订单流子代理会整份替换本文件。）
export type OrderFlowDisplay = 'all' | 'contract' | 'spot'
export interface OrderFlowSnapshot { [k: string]: unknown }
export interface OrderFlowGroupKey { [k: string]: unknown }
export const defaultOrderFlowDisplay = (): OrderFlowDisplay => 'all'
